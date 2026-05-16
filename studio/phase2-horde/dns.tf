resource "aws_route53_record" "horde" {
  #checkov:skip=CKV2_AWS_23: Aliased to ALB managed by the horde module
  zone_id = data.aws_route53_zone.studio.id
  name    = "horde.${var.route53_subdomain_zone_name}"
  type    = "A"

  alias {
    name                   = module.horde.external_alb_dns_name
    zone_id                = module.horde.external_alb_zone_id
    evaluate_target_health = true
  }
}

# Split-horizon entry for in-VPC clients. The phase1 private zone owns
# studio.sidewinder.dev for the VPC, so without this record agents (and
# anything else inside the VPC) get NXDOMAIN for horde.studio.sidewinder.dev.
# Same pattern as p4_server_private in phase1/dns.tf.
data "aws_route53_zone" "studio_private" {
  name         = var.route53_subdomain_zone_name
  private_zone = true
}

resource "aws_route53_record" "horde_private" {
  #checkov:skip=CKV2_AWS_23: Aliased to ALB managed by the horde module
  zone_id = data.aws_route53_zone.studio_private.id
  name    = "horde.${var.route53_subdomain_zone_name}"
  type    = "A"

  alias {
    name                   = module.horde.external_alb_dns_name
    zone_id                = module.horde.external_alb_zone_id
    evaluate_target_health = true
  }
}
