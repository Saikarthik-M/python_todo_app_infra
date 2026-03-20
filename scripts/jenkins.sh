#!/bin/bash
set -e

# ─────────────────────────────────────────────
# System update & base dependencies
# ─────────────────────────────────────────────
sudo apt update -y
sudo apt install -y \
  fontconfig \
  openjdk-21-jre \
  ca-certificates \
  curl \
  gnupg \
  unzip \
  wget \
  apt-transport-https \
  lsb-release \
  software-properties-common

java -version

# ─────────────────────────────────────────────
# Jenkins
# ─────────────────────────────────────────────
sudo wget -O /etc/apt/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key

echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc]" \
  https://pkg.jenkins.io/debian-stable binary/ | sudo tee \
  /etc/apt/sources.list.d/jenkins.list > /dev/null

sudo apt update -y
sudo apt install -y jenkins
sudo systemctl enable jenkins
sudo systemctl start jenkins

# ─────────────────────────────────────────────
# Install Jenkins Plugins (AWS Secrets Manager)
# ─────────────────────────────────────────────

wait_for_jenkins() {
  echo "Waiting for Jenkins to start..."
  until curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/login | grep -q "200"; do
    sleep 10
    echo "Still waiting for Jenkins..."
  done
  echo "Jenkins is up!"
}

# Wait for initial startup
wait_for_jenkins

# Download Jenkins CLI jar
wget -q http://localhost:8080/jnlpJars/jenkins-cli.jar -O /tmp/jenkins-cli.jar

# Get the initial admin password
JENKINS_PASSWORD=$(sudo cat /var/lib/jenkins/secrets/initialAdminPassword)

# Install AWS Secrets Manager plugin and its dependencies
sudo java -jar /tmp/jenkins-cli.jar \
  -s http://localhost:8080 \
  -auth admin:$JENKINS_PASSWORD \
  install-plugin \
  aws-secrets-manager-credentials-provider \
  credentials \
  credentials-binding \
  plain-credentials

echo "Plugins installed — restarting Jenkins..."

# Restart Jenkins
sudo systemctl restart jenkins

# Wait for Jenkins to come back up after restart
sleep 30
wait_for_jenkins

echo "AWS Secrets Manager plugin installed successfully!"

# ─────────────────────────────────────────────
# Docker
# ─────────────────────────────────────────────
sudo install -m 0755 -d /etc/apt/keyrings

sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update -y
sudo apt install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

sudo usermod -aG docker $USER
sudo usermod -aG docker jenkins

# ─────────────────────────────────────────────
# kubectl
# ─────────────────────────────────────────────
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
  https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /" | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null

sudo apt update -y
sudo apt install -y kubectl
kubectl version --client

# ─────────────────────────────────────────────
# kOps
# ─────────────────────────────────────────────
KOPS_VERSION=$(curl -s https://api.github.com/repos/kubernetes/kops/releases/latest \
  | grep '"tag_name"' | cut -d '"' -f4)
curl -fsSL "https://github.com/kubernetes/kops/releases/download/${KOPS_VERSION}/kops-linux-amd64" \
  -o /tmp/kops
sudo install -m 0755 /tmp/kops /usr/local/bin/kops
rm /tmp/kops
kops version

# ─────────────────────────────────────────────
# Terraform
# ─────────────────────────────────────────────
wget -O- https://apt.releases.hashicorp.com/gpg | \
  sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list > /dev/null

sudo apt update -y
sudo apt install -y terraform
terraform version

# ─────────────────────────────────────────────
# Trivy
# ─────────────────────────────────────────────
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | \
  sudo gpg --dearmor -o /usr/share/keyrings/trivy.gpg

echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] \
  https://aquasecurity.github.io/trivy-repo/deb generic main" | \
  sudo tee /etc/apt/sources.list.d/trivy.list > /dev/null

sudo apt update -y
sudo apt install -y trivy
trivy --version

# ─────────────────────────────────────────────
# Apply docker group (for current shell session)
# ─────────────────────────────────────────────
newgrp docker