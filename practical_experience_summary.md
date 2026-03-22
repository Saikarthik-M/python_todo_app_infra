# Practical Experience Summary — python_todo_app_infra

This document outlines the tools and technologies I have hands-on experience with through building the infrastructure for a Python Todo application on AWS.

---

## Tools & Technologies Used

**Terraform**
Wrote Terraform (HCL) configurations to provision AWS infrastructure from scratch — including defining resources, managing state, and handling dependencies between components.

**Kops (Kubernetes Operations)**
Used Kops to create and manage a Kubernetes cluster on AWS. Handled cluster creation, configuration, and teardown through scripted automation.

**Kubernetes**
Deployed the Python Todo application onto a Kubernetes cluster running on AWS, working with cluster lifecycle management via Kops.

**Jenkins**
Set up CI/CD pipelines using Jenkins to automate the build and deployment workflow. Managed pipeline definitions through code (Jenkinsfiles) stored in the repository.

**Docker**
Containerized the Python Todo application using Docker as part of the deployment pipeline.

**AWS**
Provisioned and managed cloud infrastructure on Amazon Web Services, integrating it with Terraform and Kops for automated resource management.

**Shell Scripting (Bash)**
Wrote shell scripts to automate infrastructure tasks — including a dedicated destroy script that handles both Kops cluster teardown and Terraform resource destruction in the correct sequence.

---

> All of the above was done practically as part of building and deploying the `python_todo_app_infra` project end-to-end.
