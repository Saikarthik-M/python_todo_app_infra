resource "aws_vpc" "this" {
  cidr_block = var.cidr_block

  tags = {
    Name = var.name
  }
}

#subnet 

resource "aws_subnet" "public" {
  count = length(var.public_subnets)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnets[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.name}-public-${count.index}"
  }
}

resource "aws_subnet" "private" {
  count = length(var.private_subnets)

  vpc_id     = aws_vpc.this.id
  cidr_block = var.private_subnets[count.index]

  tags = {
    Name = "${var.name}-private-${count.index}"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
}

# public route table

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.this.id
}

resource "aws_route_table_association" "public_rta" {
  count          = length(aws_subnet.public)
  route_table_id = aws_route_table.public_rt.id
  subnet_id      = aws_subnet.public[count.index].id
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

# private route table

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.this.id
}

resource "aws_route_table_association" "private_rta" {
  count          = length(aws_subnet.private)
  route_table_id = aws_route_table.private_rt.id
  subnet_id      = aws_subnet.private[count.index].id
}

resource "aws_route" "private_route" {
  route_table_id         = aws_route_table.private_rt.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat.primary_network_interface_id
}

module "nat_sg" {
  source = "../sg"

  name   = "nat_sg"
  vpc_id = aws_vpc.this.id

  ingress = [{
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.cidr_block]
  }]

  egress = [{
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }]
}

resource "aws_instance" "nat" {
  ami                         = var.nat_ami
  instance_type               = var.nat_instance_type
  subnet_id                   = aws_subnet.public[0].id
  associate_public_ip_address = true
  source_dest_check           = false
  vpc_security_group_ids      = [module.nat_sg.sg_id]
  user_data                   = file("${path.root}/../scripts/nat.sh")
  key_name = var.nat_key_name
  tags = {
    Name = "nat-instance"
  }
}
