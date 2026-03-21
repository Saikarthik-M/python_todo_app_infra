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
echo "KOPS_STATE_STORE: ${KOPS_STATE_STORE}"

cd ..

# ─────────────────────────────────────────────
# Verify kOps Cluster Exists
# ─────────────────────────────────────────────
echo "Checking if kOps cluster exists..."
if kops get cluster --name=${CLUSTER_NAME} --state=${KOPS_STATE_STORE} > /dev/null 2>&1; then
  SKIP_KOPS="false"
  echo "Cluster found — will delete."
else
  SKIP_KOPS="true"
  echo "Cluster not found — skipping kOps delete."
fi

# ─────────────────────────────────────────────
# kOps Delete Cluster
# ─────────────────────────────────────────────
if [ "${SKIP_KOPS}" == "false" ]; then
  echo "Deleting kOps cluster..."
  kops delete cluster \
    --name=${CLUSTER_NAME} \
    --state=${KOPS_STATE_STORE} \
    --yes

  # ─────────────────────────────────────────────
  # Verify kOps Resources Gone
  # ─────────────────────────────────────────────
  echo "Verifying kOps resources are gone..."
  aws ec2 describe-instances \
    --region=${AWS_REGION} \
    --filters "Name=tag:KubernetesCluster,Values=${CLUSTER_NAME}" \
              "Name=instance-state-name,Values=running,pending,stopping" \
    --query 'Reservations[].Instances[].InstanceId' \
    --output text
fi

# ─────────────────────────────────────────────
# Empty kOps State Bucket
# ─────────────────────────────────────────────
echo "Emptying kOps state bucket..."
BUCKET_NAME=$(cd ${TF_DIR} && terraform output -raw kops_bucket_name)

# Delete all objects
aws s3 rm s3://${BUCKET_NAME} --recursive --region ${AWS_REGION}

# Delete all versions and delete markers
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

echo "All infrastructure destroyed successfully."