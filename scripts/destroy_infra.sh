#!/bin/bash
set -e

AWS_REGION="ap-south-1"
CLUSTER_NAME="mypythonapp.k8s.local"
TF_DIR="terraform"

# ─────────────────────────────────────────────
# Get Terraform Outputs
# ─────────────────────────────────────────────
echo "Initializing Terraform..."
cd ${TF_DIR}
terraform init -reconfigure

KOPS_STATE_STORE="s3://$(terraform output -raw kops_bucket_name)"
BUCKET_NAME=$(terraform output -raw kops_bucket_name)
VPC_ID=$(terraform output -raw vpc_id)
echo "KOPS_STATE_STORE: ${KOPS_STATE_STORE}"
echo "VPC_ID: ${VPC_ID}"

cd ..

# ─────────────────────────────────────────────
# kOps Delete Cluster
# ─────────────────────────────────────────────
echo "Checking if kOps cluster exists..."
if kops get cluster --name=${CLUSTER_NAME} --state=${KOPS_STATE_STORE} > /dev/null 2>&1; then
    echo "Cluster found — deleting..."
    kops delete cluster \
      --name=${CLUSTER_NAME} \
      --state=${KOPS_STATE_STORE} \
      --yes
else
    echo "Cluster not found — skipping kOps delete."
fi

# ─────────────────────────────────────────────
# Wait for kOps Instances to Terminate
# ─────────────────────────────────────────────
echo "Waiting for kOps instances to terminate..."
MAX_WAIT=300  # 5 minutes max
ELAPSED=0
while true; do
    RUNNING=$(aws ec2 describe-instances \
      --filters "Name=tag:KubernetesCluster,Values=${CLUSTER_NAME}" \
                "Name=instance-state-name,Values=running,pending,stopping" \
      --query "Reservations[*].Instances[*].InstanceId" \
      --output text \
      --region ${AWS_REGION})

    if [ -z "$RUNNING" ]; then
        echo "All kOps instances terminated ✅"
        break
    fi

    if [ $ELAPSED -ge $MAX_WAIT ]; then
        echo "Timeout — force terminating remaining instances..."
        echo $RUNNING | tr '\t' '\n' | \
          xargs -I {} aws ec2 terminate-instances \
          --instance-ids {} --region ${AWS_REGION}
        aws ec2 wait instance-terminated \
          --instance-ids $(echo $RUNNING | tr '\t' ' ') \
          --region ${AWS_REGION}
        break
    fi

    echo "Still waiting for instances... (${ELAPSED}s elapsed)"
    sleep 15
    ELAPSED=$((ELAPSED + 15))
done

# ─────────────────────────────────────────────
# Delete Leftover ELBs (Nginx Ingress + API ELB)
# ─────────────────────────────────────────────
echo "Deleting leftover ELBs..."

# Classic ELBs
aws elb describe-load-balancers \
  --region ${AWS_REGION} \
  --query "LoadBalancerDescriptions[*].LoadBalancerName" \
  --output text | tr '\t' '\n' | \
  xargs -I {} aws elb delete-load-balancer \
  --load-balancer-name {} --region ${AWS_REGION} 2>/dev/null || true

# ALB/NLB ELBs
aws elbv2 describe-load-balancers \
  --region ${AWS_REGION} \
  --query "LoadBalancers[*].LoadBalancerArn" \
  --output text | tr '\t' '\n' | \
  xargs -I {} aws elbv2 delete-load-balancer \
  --load-balancer-arn {} --region ${AWS_REGION} 2>/dev/null || true

echo "Waiting for ELBs to be fully deleted..."
sleep 30

# ─────────────────────────────────────────────
# Delete Leftover Security Groups
# ─────────────────────────────────────────────
echo "Deleting leftover kOps Security Groups..."
aws ec2 describe-security-groups \
  --filters "Name=tag:KubernetesCluster,Values=${CLUSTER_NAME}" \
  --query "SecurityGroups[*].GroupId" \
  --output text \
  --region ${AWS_REGION} | tr '\t' '\n' | \
  xargs -I {} aws ec2 delete-security-group \
  --group-id {} --region ${AWS_REGION} 2>/dev/null || true

sleep 10

# ─────────────────────────────────────────────
# Delete Leftover ENIs in VPC
# ─────────────────────────────────────────────
echo "Deleting leftover ENIs..."
aws ec2 describe-network-interfaces \
  --filters "Name=vpc-id,Values=${VPC_ID}" \
            "Name=status,Values=available" \
  --query "NetworkInterfaces[*].NetworkInterfaceId" \
  --output text \
  --region ${AWS_REGION} | tr '\t' '\n' | \
  xargs -I {} aws ec2 delete-network-interface \
  --network-interface-id {} --region ${AWS_REGION} 2>/dev/null || true

sleep 10

# ─────────────────────────────────────────────
# Empty kOps State Bucket
# ─────────────────────────────────────────────
echo "Emptying kOps state bucket..."

aws s3 rm s3://${BUCKET_NAME} --recursive --region ${AWS_REGION}

for VERSION_TYPE in Versions DeleteMarkers; do
  OBJECTS=$(aws s3api list-object-versions \
    --bucket ${BUCKET_NAME} \
    --query "{Objects: ${VERSION_TYPE}[].{Key:Key,VersionId:VersionId}}" \
    --output json 2>/dev/null)

  if [ "$(echo $OBJECTS | jq '.Objects | length')" -gt "0" ]; then
    aws s3api delete-objects \
      --bucket ${BUCKET_NAME} \
      --delete "$OBJECTS" \
      --region ${AWS_REGION}
  fi
done

echo "Bucket emptied successfully."

# ─────────────────────────────────────────────
# Terraform Destroy
# ─────────────────────────────────────────────
echo "Running Terraform destroy..."
cd ${TF_DIR}
terraform init -reconfigure
terraform destroy -auto-approve

echo "✅ All infrastructure destroyed successfully."