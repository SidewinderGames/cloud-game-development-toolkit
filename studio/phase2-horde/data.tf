data "aws_route53_zone" "studio" {
  name         = var.route53_subdomain_zone_name
  private_zone = false
}
