resource "aws_vpc" "studio" {
  cidr_block           = local.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  #checkov:skip=CKV2_AWS_11: VPC flow logs deferred for cost; revisit at scale-up
  tags = {
    Name = "${local.project_prefix}-studio-vpc"
  }
}

resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.studio.id

  tags = {
    Name = "${local.project_prefix}-default-locked"
  }
}

resource "aws_subnet" "public" {
  count                   = length(local.public_subnet_cidrs)
  vpc_id                  = aws_vpc.studio.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.project_prefix}-public-${count.index + 1}"
    Tier = "public"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.studio.id

  tags = {
    Name = "${local.project_prefix}-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.studio.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${local.project_prefix}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  route_table_id = aws_route_table.public.id
  subnet_id      = aws_subnet.public[count.index].id
}
