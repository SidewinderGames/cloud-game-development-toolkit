data "aws_route53_zone" "studio" {
  name         = var.route53_subdomain_zone_name
  private_zone = false
}

resource "aws_acm_certificate" "studio_wildcard" {
  domain_name       = "*.${var.route53_subdomain_zone_name}"
  validation_method = "DNS"

  #checkov:skip=CKV2_AWS_71: Wildcard required so both p4.studio... and horde.studio... share one cert.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.studio_wildcard.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  zone_id         = data.aws_route53_zone.studio.id
  name            = each.value.name
  records         = [each.value.record]
  type            = each.value.type
  ttl             = 60
}

resource "aws_acm_certificate_validation" "studio_wildcard" {
  certificate_arn         = aws_acm_certificate.studio_wildcard.arn
  validation_record_fqdns = [for r in aws_route53_record.acm_validation : r.fqdn]

  timeouts {
    create = "45m"
  }
}

resource "aws_route53_record" "p4_server" {
  #checkov:skip=CKV2_AWS_23: Attached to EIP public IP
  zone_id = data.aws_route53_zone.studio.id
  name    = local.p4_server_fqdn
  type    = "A"
  ttl     = 300
  records = [module.perforce.p4_server_eip_public_ip]
}
