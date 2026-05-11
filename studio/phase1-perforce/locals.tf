provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.tags
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  project_prefix = "sidewinder"

  vpc_cidr            = "10.40.0.0/16"
  public_subnet_cidrs = ["10.40.1.0/24", "10.40.2.0/24"]

  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  p4_server_fqdn = "p4.${var.route53_subdomain_zone_name}"
}
