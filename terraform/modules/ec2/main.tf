resource "aws_instance" "this" {
  ami                         = var.ami
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = var.sg_ids
  key_name                    = var.key_name
  associate_public_ip_address = var.associate_public_ip_address
  user_data                   = var.user_data
  iam_instance_profile        = var.iam_instance_profile
  tags = {
    Name = var.name
  }
  root_block_device {
    volume_size           = var.volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }
}
