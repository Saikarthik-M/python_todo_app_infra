# python_todo_app_infra

Infrastructure-as-Code (IaC) repository for provisioning and managing the cloud infrastructure of the **Python Todo App**. This repo automates environment setup, CI/CD pipeline configuration, and cloud resource provisioning using **Terraform**, **Shell scripts**, and **Jenkins**.

---

## 📁 Repository Structure

```
python_todo_app_infra/
├── terraform/              # Terraform configurations for cloud infrastructure
├── jenkins/
│   └── createOrUpdate/     # Jenkins pipeline definitions (create/update jobs)
├── scripts/                # Shell scripts for automation and bootstrapping
├── config/                 # Environment and application configuration files
└── .gitignore
```

---

## 🛠️ Tech Stack

| Tool        | Purpose                                      |
|-------------|----------------------------------------------|
| Terraform   | Cloud infrastructure provisioning (IaC)      |
| Shell / Bash| Automation scripts for setup and deployment  |
| Jenkins     | CI/CD pipeline creation and management       |

---

## 🚀 Getting Started

### Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.0
- AWS CLI (or relevant cloud provider CLI) configured with appropriate credentials
- Jenkins instance (if using the pipeline definitions)
- Bash shell environment

### Clone the Repository

```bash
git clone https://github.com/Saikarthik-M/python_todo_app_infra.git
cd python_todo_app_infra
```

---

## ⚙️ Infrastructure Provisioning (Terraform)

```bash
cd terraform/

# Initialize Terraform
terraform init

# Preview the planned changes
terraform plan

# Apply the infrastructure
terraform apply
```

To destroy the infrastructure, use the dedicated destroy script instead of running `terraform destroy` directly. The script handles both **kops** cluster teardown and **Terraform** resource destruction in the correct order:

```bash
./scripts/destroy.sh
```

> **Note:** Ensure your cloud credentials and any required `terraform.tfvars` values are configured before running.

---

## 🔧 Scripts

The `scripts/` directory contains shell scripts for tasks such as:

- Environment bootstrapping
- Deployment automation
- Health checks or utility helpers

Run scripts with appropriate permissions:

```bash
chmod +x scripts/<script-name>.sh
./scripts/<script-name>.sh
```

---

## 🏗️ Jenkins Pipelines

The `jenkins/createOrUpdate/` directory contains Groovy/Jenkinsfile definitions for creating or updating CI/CD jobs.

To use:
1. Log in to your Jenkins instance.
2. Use the Job DSL or Jenkins CLI to apply the pipeline definitions from `jenkins/createOrUpdate/`.

---

## 📋 Configuration

The `config/` directory holds the configuration files for the project.

---

## 👤 Author

**Saikarthik M** — [GitHub](https://github.com/Saikarthik-M)
