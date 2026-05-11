data "aws_vpc" "studio" {
  filter {
    name   = "tag:Name"
    values = ["sidewinder-studio-vpc"]
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.studio.id]
  }
  filter {
    name   = "tag:Tier"
    values = ["public"]
  }
}

data "aws_route53_zone" "studio" {
  name         = var.route53_subdomain_zone_name
  private_zone = false
}

data "aws_acm_certificate" "studio_wildcard" {
  domain      = "*.${var.route53_subdomain_zone_name}"
  statuses    = ["ISSUED"]
  most_recent = true
}
