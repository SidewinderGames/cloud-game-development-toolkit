output "p4_port" {
  description = "Connection string for P4V. Set this as P4PORT."
  value       = "ssl:${local.p4_server_fqdn}:1666"
}

output "p4_server_eip" {
  description = "Public IP of the P4 server."
  value       = module.perforce.p4_server_eip_public_ip
}

output "p4_server_instance_id" {
  description = "EC2 instance ID for the P4 server (useful for SSM Session Manager)."
  value       = module.perforce.p4_server_instance_id
}

output "p4_admin_username_secret_arn" {
  description = "Secrets Manager ARN for the P4 admin username."
  value       = module.perforce.p4_server_admin_username_secret_arn
}

output "p4_admin_password_secret_arn" {
  description = "Secrets Manager ARN for the P4 admin password."
  value       = module.perforce.p4_server_admin_password_secret_arn
}

output "p4_super_password_secret_arn" {
  description = "Secrets Manager ARN for the P4 super-user (service account) password. Phase 2 Horde reuses this."
  value       = module.perforce.p4_server_super_password_secret_arn
}

output "studio_vpc_id" {
  description = "VPC ID consumed by Phase 2."
  value       = aws_vpc.studio.id
}

output "studio_public_subnet_ids" {
  description = "Public subnet IDs consumed by Phase 2."
  value       = aws_subnet.public[*].id
}

output "studio_wildcard_certificate_arn" {
  description = "Wildcard ACM cert ARN reusable by Phase 2 for the Horde ALB."
  value       = aws_acm_certificate_validation.studio_wildcard.certificate_arn
}

output "studio_route53_zone_id" {
  description = "Route53 zone ID for studio.sidewinder.dev."
  value       = data.aws_route53_zone.studio.id
}

output "tailscale_relay_instance_id" {
  description = "EC2 instance ID of the Tailscale subnet router (if enabled)."
  value       = var.create_tailscale_relay ? aws_instance.tailscale_relay[0].id : null
}

output "tailscale_relay_security_group_id" {
  description = "Security group attached to the Tailscale subnet router."
  value       = var.create_tailscale_relay ? aws_security_group.tailscale_relay[0].id : null
}

output "tailscale_relay_public_ip" {
  description = "Public IP of the Tailscale relay (for direct SSH if Tailscale is unreachable for debugging). Routine access uses Tailscale."
  value       = var.create_tailscale_relay ? aws_instance.tailscale_relay[0].public_ip : null
}
