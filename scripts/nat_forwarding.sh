#!/bin/bash

BASTION_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=bastion_host" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].PublicIpAddress" \
  --output text)

JENKINS_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=jenkins_instance" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].PrivateIpAddress" \
  --output text)

echo "Bastion IP: $BASTION_IP"
echo "Jenkins Private IP: $JENKINS_IP"

# Add key to ssh agent
ssh-add ./config/id_rsa_devops

# Copy key to bastion
scp -i "./config/id_rsa_devops" ./config/id_rsa_devops ubuntu@${BASTION_IP}:/home/ubuntu/id_rsa_devops

# Fix key permissions on bastion
ssh -i "./config/id_rsa_devops" ubuntu@${BASTION_IP} "chmod 400 /home/ubuntu/id_rsa_devops"

# Get Jenkins initial admin password
# -A flag forwards your local ssh agent to bastion
# so bastion can use your local key to reach Jenkins
echo "Jenkins Initial Admin Password:"
ssh -i "./config/id_rsa_devops" \
  -A \
  -o StrictHostKeyChecking=no \
  ubuntu@${BASTION_IP} \
  "ssh -o StrictHostKeyChecking=no ubuntu@${JENKINS_IP} 'sudo cat /var/lib/jenkins/secrets/initialAdminPassword'"

# Open SSH tunnel for Jenkins UI
ssh -i "./config/id_rsa_devops" -A -L 8080:${JENKINS_IP}:8080 ubuntu@${BASTION_IP}