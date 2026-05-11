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
