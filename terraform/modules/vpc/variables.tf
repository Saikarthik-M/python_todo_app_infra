variable "name" {
  description = "VPC name"
  type        = string
}

variable "cidr_block" {
  description = "VPC CIDR"
  type        = string
}

variable "public_subnets" {
  description = "Public subnet CIDRs"
  type        = list(string)
}

variable "private_subnets" {
  description = "Private subnet CIDRs"
  type        = list(string)
}

variable "nat_instance_type" {
  description = "Instance Type"
  type = string
}

variable "nat_ami" {
  description = "AMI ID"
  type = string
}

variable "nat_key_name" {
  description = "Key Name for NAT SSH"
  type = string
}

variable "availability_zone" {
  description = "Availability zone of region"
  type = string
}