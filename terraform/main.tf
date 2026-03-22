provider "aws" {
  region = "ap-south-1"
}

module "vpc" {
  source            = "./modules/vpc"
  name              = "my-vpc"
  cidr_block        = "10.0.0.0/16"
  public_subnets    = ["10.0.1.0/24"]
  private_subnets   = ["10.0.3.0/24"]
  nat_instance_type = "t3.small"
  nat_ami           = "ami-05d2d839d4f73aafb"
  nat_key_name = module.key_name.key_name
  availability_zone = "ap-south-1a"
}

module "jenkins_sg" {
  source = "./modules/sg"
  name   = "jenkins_sg"
  ingress = [{
    from_port       = 8080
    to_port         = 8080
    protocol        = "TCP"
    security_groups = [module.bastion_host_sg.sg_id]
    },
    {
      from_port       = 22
      to_port         = 22
      protocol        = "TCP"
      security_groups = [module.bastion_host_sg.sg_id]
  }]
  egress = [{
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    }
  ]
  vpc_id = module.vpc.vpc_id
}

module "bastion_host_sg" {
  source = "./modules/sg"
  name   = "bastion_host_sg"
  ingress = [{
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 22
    to_port     = 22
    protocol    = "TCP"
  }]
  egress = [{
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
  }]
  vpc_id = module.vpc.vpc_id
}

module "key_name" {
  source     = "./modules/key_name"
  key_name   = "python_app_key"
  public_key = file("${path.module}/../config/id_rsa_devops.pub")
}

module "jenkins_role" {
  source = "./modules/iam"

  name = "jenkins-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  policy_arns = [
      "arn:aws:iam::aws:policy/SecretsManagerReadWrite",
      "arn:aws:iam::aws:policy/IAMFullAccess",          
      "arn:aws:iam::aws:policy/AmazonEC2FullAccess",    
      "arn:aws:iam::aws:policy/AmazonS3FullAccess",
      "arn:aws:iam::aws:policy/CloudWatchEventsFullAccess",
      "arn:aws:iam::aws:policy/AmazonSQSFullAccess"
  ]
}



module "jenkins_instance" {
  source        = "./modules/ec2"
  instance_type = "t3.small"
  ami           = "ami-05d2d839d4f73aafb"
  name          = "jenkins_instance"
  subnet_id     = module.vpc.private_subnet_ids[0]
  sg_ids        = [module.jenkins_sg.sg_id]
  key_name      = module.key_name.key_name
  user_data = file("${path.module}/../scripts/jenkins.sh")
  iam_instance_profile = module.jenkins_role.instance_profile_name
  volume_size = 50
}

module "bastion_host" {
  source                      = "./modules/ec2"
  instance_type               = "t3.small"
  ami                         = "ami-05d2d839d4f73aafb"
  name                        = "bastion_host"
  subnet_id                   = module.vpc.public_subnet_ids[0]
  sg_ids                      = [module.bastion_host_sg.sg_id]
  key_name                    = module.key_name.key_name
  associate_public_ip_address = true
}

module "kops_s3" {
  source = "./modules/s3"
  versioning = "Enabled"
  bucket_name = "saikarthik-python-app-kops-state"
  force_destroy = true
}

terraform {
  backend "s3" {
    bucket         = "saikarthik-python-app-tf-state"
    key            = "terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
  }
}

