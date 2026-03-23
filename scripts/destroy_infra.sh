#!/bin/bash

# Note: removed set -e so cleanup continues even if one step fails
AWS_REGION="ap-south-1"
CLUSTER_NAME="mypythonapp.k8s.local"
TF_DIR="terraform"

echo "========================================"
echo " Full Infrastructure Destroy Script"
echo "========================================"

# ─────────────────────────────────────────────
# Get Terraform Outputs
# ─────────────────────────────────────────────
echo ""
echo "Step 1: Getting Terraform outputs..."
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
echo ""
echo "Step 2: Deleting kOps cluster..."
if kops get cluster --name=${CLUSTER_NAME} --state=${KOPS_STATE_STORE} > /dev/null 2>&1; then
    echo "Cluster found — deleting..."
    kops delete cluster \
      --name=${CLUSTER_NAME} \
      --state=${KOPS_STATE_STORE} \
      --yes
    echo "kOps cluster deleted ✅"
else
    echo "Cluster not found — skipping."
fi

# ─────────────────────────────────────────────
# Delete ASGs First (prevents instance recreation)
# ─────────────────────────────────────────────
echo ""
echo "Step 3: Deleting Auto Scaling Groups..."
ASGS=$(aws autoscaling describe-auto-scaling-groups \
  --region ${AWS_REGION} \
  --query "AutoScalingGroups[?contains(Tags[?Key=='KubernetesCluster'].Value, '${CLUSTER_NAME}')].AutoScalingGroupName" \
  --output text)

if [ -n "$ASGS" ]; then
    echo "$ASGS" | tr '\t' '\n' | while read ASG; do
        [ -z "$ASG" ] && continue
        echo "  Deleting ASG: $ASG"
        aws autoscaling delete-auto-scaling-group \
          --auto-scaling-group-name "$ASG" \
          --force-delete \
          --region ${AWS_REGION} 2>/dev/null || true
    done
    echo "Waiting 60s for ASG instances to terminate..."
    sleep 60
else
    echo "No ASGs found — skipping."
fi

# ─────────────────────────────────────────────
# Wait for All Instances to Terminate
# ─────────────────────────────────────────────
echo ""
echo "Step 4: Waiting for instances to terminate..."
MAX_WAIT=300
ELAPSED=0
while true; do
    RUNNING=$(aws ec2 describe-instances \
      --filters "Name=vpc-id,Values=${VPC_ID}" \
                "Name=instance-state-name,Values=running,pending,stopping" \
      --query "Reservations[*].Instances[*].InstanceId" \
      --output text \
      --region ${AWS_REGION})

    if [ -z "$RUNNING" ]; then
        echo "All instances terminated ✅"
        break
    fi

    if [ $ELAPSED -ge $MAX_WAIT ]; then
        echo "Timeout — force terminating remaining instances..."
        echo "$RUNNING" | tr '\t' '\n' | while read ID; do
            [ -z "$ID" ] && continue
            echo "  Terminating: $ID"
            aws ec2 terminate-instances \
              --instance-ids "$ID" \
              --region ${AWS_REGION} 2>/dev/null || true
        done

        # Wait for each instance individually
        echo "$RUNNING" | tr '\t' '\n' | while read ID; do
            [ -z "$ID" ] && continue
            echo "  Waiting for $ID..."
            aws ec2 wait instance-terminated \
              --instance-ids "$ID" \
              --region ${AWS_REGION} 2>/dev/null || true
        done
        break
    fi

    echo "Still waiting... (${ELAPSED}s) Instances: $RUNNING"
    sleep 15
    ELAPSED=$((ELAPSED + 15))
done

# ─────────────────────────────────────────────
# Delete Leftover ELBs
# ─────────────────────────────────────────────
echo ""
echo "Step 5: Deleting leftover ELBs..."

# Classic ELBs
aws elb describe-load-balancers \
  --region ${AWS_REGION} \
  --query "LoadBalancerDescriptions[*].LoadBalancerName" \
  --output text 2>/dev/null | tr '\t' '\n' | while read ELB; do
    [ -z "$ELB" ] && continue
    echo "  Deleting Classic ELB: $ELB"
    aws elb delete-load-balancer \
      --load-balancer-name "$ELB" \
      --region ${AWS_REGION} 2>/dev/null || true
done

# ALB/NLB ELBs
aws elbv2 describe-load-balancers \
  --region ${AWS_REGION} \
  --query "LoadBalancers[*].LoadBalancerArn" \
  --output text 2>/dev/null | tr '\t' '\n' | while read ELB; do
    [ -z "$ELB" ] && continue
    echo "  Deleting ALB/NLB: $ELB"
    aws elbv2 delete-load-balancer \
      --load-balancer-arn "$ELB" \
      --region ${AWS_REGION} 2>/dev/null || true
done

echo "Waiting 30s for ELBs to delete..."
sleep 30
echo "ELBs deleted ✅"

# ─────────────────────────────────────────────
# Delete Target Groups
# ─────────────────────────────────────────────
echo ""
echo "Step 6: Deleting Target Groups..."
aws elbv2 describe-target-groups \
  --region ${AWS_REGION} \
  --query "TargetGroups[*].TargetGroupArn" \
  --output text 2>/dev/null | tr '\t' '\n' | while read TG; do
    [ -z "$TG" ] && continue
    echo "  Deleting TG: $TG"
    aws elbv2 delete-target-group \
      --target-group-arn "$TG" \
      --region ${AWS_REGION} 2>/dev/null || true
done
echo "Target Groups deleted ✅"

# ─────────────────────────────────────────────
# Release Elastic IPs
# ─────────────────────────────────────────────
echo ""
echo "Step 7: Releasing Elastic IPs..."

# Disassociate first
aws ec2 describe-addresses \
  --region ${AWS_REGION} \
  --query "Addresses[?AssociationId!=null].AssociationId" \
  --output text | tr '\t' '\n' | while read ASSOC; do
    [ -z "$ASSOC" ] && continue
    aws ec2 disassociate-address \
      --association-id "$ASSOC" \
      --region ${AWS_REGION} 2>/dev/null || true
done

# Release all
aws ec2 describe-addresses \
  --region ${AWS_REGION} \
  --query "Addresses[*].AllocationId" \
  --output text | tr '\t' '\n' | while read EIP; do
    [ -z "$EIP" ] && continue
    echo "  Releasing EIP: $EIP"
    aws ec2 release-address \
      --allocation-id "$EIP" \
      --region ${AWS_REGION} 2>/dev/null || true
done
echo "Elastic IPs released ✅"

# ─────────────────────────────────────────────
# Clear Security Group Rules (cross-references)
# ─────────────────────────────────────────────
echo ""
echo "Step 8: Clearing Security Group rules..."
aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=${VPC_ID}" \
  --query "SecurityGroups[?GroupName!='default'].GroupId" \
  --output text \
  --region ${AWS_REGION} | tr '\t' '\n' | while read SG; do
    [ -z "$SG" ] && continue
    echo "  Clearing rules for: $SG"

    # Clear ingress
    INGRESS=$(aws ec2 describe-security-groups \
      --group-ids "$SG" \
      --query "SecurityGroups[0].IpPermissions" \
      --output json --region ${AWS_REGION} 2>/dev/null)
    if [ "$INGRESS" != "[]" ] && [ -n "$INGRESS" ]; then
        aws ec2 revoke-security-group-ingress \
          --group-id "$SG" \
          --ip-permissions "$INGRESS" \
          --region ${AWS_REGION} 2>/dev/null || true
    fi

    # Clear egress
    EGRESS=$(aws ec2 describe-security-groups \
      --group-ids "$SG" \
      --query "SecurityGroups[0].IpPermissionsEgress" \
      --output json --region ${AWS_REGION} 2>/dev/null)
    if [ "$EGRESS" != "[]" ] && [ -n "$EGRESS" ]; then
        aws ec2 revoke-security-group-egress \
          --group-id "$SG" \
          --ip-permissions "$EGRESS" \
          --region ${AWS_REGION} 2>/dev/null || true
    fi
done

# Delete Security Groups
echo "Deleting Security Groups..."
aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=${VPC_ID}" \
  --query "SecurityGroups[?GroupName!='default'].GroupId" \
  --output text \
  --region ${AWS_REGION} | tr '\t' '\n' | while read SG; do
    [ -z "$SG" ] && continue
    echo "  Deleting SG: $SG"
    aws ec2 delete-security-group \
      --group-id "$SG" \
      --region ${AWS_REGION} 2>/dev/null || true
done
echo "Security Groups deleted ✅"

sleep 10

# ─────────────────────────────────────────────
# Delete Leftover ENIs
# ─────────────────────────────────────────────
echo ""
echo "Step 9: Deleting leftover ENIs..."
aws ec2 describe-network-interfaces \
  --filters "Name=vpc-id,Values=${VPC_ID}" \
            "Name=status,Values=available" \
  --query "NetworkInterfaces[*].NetworkInterfaceId" \
  --output text \
  --region ${AWS_REGION} | tr '\t' '\n' | while read ENI; do
    [ -z "$ENI" ] && continue
    echo "  Deleting ENI: $ENI"
    aws ec2 delete-network-interface \
      --network-interface-id "$ENI" \
      --region ${AWS_REGION} 2>/dev/null || true
done
echo "ENIs deleted ✅"

sleep 10

# ─────────────────────────────────────────────
# Empty kOps State Bucket
# ─────────────────────────────────────────────
echo ""
echo "Step 10: Emptying kOps state bucket..."
aws s3 rm s3://${BUCKET_NAME} --recursive --region ${AWS_REGION} 2>/dev/null || true

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
echo "Bucket emptied ✅"

# ─────────────────────────────────────────────
# Terraform Destroy
# ─────────────────────────────────────────────
echo ""
echo "Step 11: Running Terraform destroy..."
cd ${TF_DIR}
terraform init -reconfigure
terraform destroy -auto-approve

echo ""
echo "========================================"
echo " ✅ All infrastructure destroyed!"
echo "========================================"