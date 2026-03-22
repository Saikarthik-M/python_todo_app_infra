variable "name" {
    description = "name of the ec2 instance"
    type = string
}
variable "ami" {
    description = "AMI ID"
    type = string
}
variable "instance_type" {
    description = "Type of Instance like t2.small,t2.medium.."
    type = string
}
variable "subnet_id" {
    description = "subnet ID of Instance"
    type = string
}
variable "sg_ids" {
    description = "security group id list"
  type = list(string)
}
variable "key_name" {
    description = "ssh key id"
    type = string
}
variable "associate_public_ip_address" {
    description = "Associate Public IP address"
    type = bool
    default = false
}
variable "user_data" {
  description = "Script to run after installation"
  type = string
  default = null
}

variable "iam_instance_profile" {
    description = "IAM Role"
    type = string
    default = null
}

variable "volume_size" {
  description = "Volume Size"
  type = number
  default = 8
}