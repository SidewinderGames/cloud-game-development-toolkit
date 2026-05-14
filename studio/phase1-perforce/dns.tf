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

###############################################################
# Private split-horizon zone for in-VPC name resolution.
#
# Horde agents (Phase 2) need to reach the P4 server on tcp/1666
# via the public FQDN p4.studio.sidewinder.dev, but routing through
# the public IP loses the source SG context for SG-to-SG rules.
# Agent traffic hits the P4 SG as its public IP and gets dropped.
#
# A private hosted zone for the same domain, associated with our
# VPC, makes in-VPC clients resolve the FQDN to the P4 instance's
# PRIVATE IP. Traffic then stays inside the VPC and the SG-to-SG
# rule on port 1666 matches, no public hairpinning involved.
#
# External clients (laptops, build farms outside the VPC) keep
# resolving via the public zone -> public IP -> EIP. Same FQDN,
# split-horizon answers.
###############################################################
resource "aws_route53_zone" "studio_private" {
  name = var.route53_subdomain_zone_name

  vpc {
    vpc_id = aws_vpc.studio.id
  }

  comment = "Split-horizon private zone for in-VPC name resolution (P4 agent ingress fix)"

  tags = {
    Studio = "Sidewinder"
  }
}

resource "aws_route53_record" "p4_server_private" {
  zone_id = aws_route53_zone.studio_private.zone_id
  name    = local.p4_server_fqdn
  type    = "A"
  ttl     = 60
  records = [module.perforce.p4_server_private_ip]
}
