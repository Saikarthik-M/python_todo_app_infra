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
# Terraform Destroy
# ─────────────────────────────────────────────
echo "Running Terraform destroy..."
cd ${TF_DIR}
terraform init -reconfigure
terraform destroy -auto-approve

echo "All infrastructure destroyed successfully."