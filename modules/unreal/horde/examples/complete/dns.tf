data "aws_route53_zone" "root" {
  name         = var.root_domain_name
  private_zone = false
}

resource "aws_route53_record" "unreal_engine_horde_external" {
  #checkov:skip=CKV2_AWS_23: Aliased to ALB managed by this module
  zone_id = data.aws_route53_zone.root.id
  name    = "horde.${data.aws_route53_zone.root.name}"
  type    = "A"

  alias {
    name                   = module.unreal_engine_horde.external_alb_dns_name
    zone_id                = module.unreal_engine_horde.external_alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_acm_certificate" "unreal_engine_horde" {
  domain_name       = "horde.${data.aws_route53_zone.root.name}"
  validation_method = "DNS"

  tags = {
    environment = "dev"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "unreal_engine_horde_cert" {
  for_each = {
    for dvo in aws_acm_certificate.unreal_engine_horde.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.root.id
}

resource "aws_acm_certificate_validation" "unreal_engine_horde" {
  certificate_arn         = aws_acm_certificate.unreal_engine_horde.arn
  validation_record_fqdns = [for record in aws_route53_record.unreal_engine_horde_cert : record.fqdn]

  timeouts {
    create = "45m"
  }
}
