output "external_alb_dns_name" {
  description = "DNS name of the external Horde ALB."
  value       = var.create_external_alb ? aws_lb.unreal_horde_external_alb[0].dns_name : null
}

output "external_alb_zone_id" {
  description = "Hosted zone ID of the external Horde ALB (for Route53 ALIAS records)."
  value       = var.create_external_alb ? aws_lb.unreal_horde_external_alb[0].zone_id : null
}

output "external_alb_sg_id" {
  description = "Security group attached to the external Horde ALB."
  value       = var.create_external_alb ? aws_security_group.unreal_horde_external_alb_sg[0].id : null
}

output "service_security_group_id" {
  description = "Security group attached to the Horde host (formerly the ECS service SG)."
  value       = aws_security_group.unreal_horde_sg.id
}

output "agent_security_group_id" {
  description = "Security group attached to Horde agent ASG instances."
  value       = length(var.agents) > 0 ? aws_security_group.unreal_horde_agent_sg[0].id : null
}

output "horde_host_instance_id" {
  description = "EC2 instance ID of the Horde all-in-one host."
  value       = aws_instance.horde_host.id
}

output "horde_host_private_ip" {
  description = "Private IP address of the Horde host."
  value       = aws_instance.horde_host.private_ip
}

output "horde_host_public_ip" {
  description = "Public IP of the Horde host (used for IGW egress without NAT). The host should be reached via the ALB, not this IP."
  value       = aws_instance.horde_host.public_ip
}

output "horde_storage_bucket_name" {
  description = "Name of the S3 bucket used for Horde artifact and log storage."
  value       = var.create_s3_storage_bucket ? aws_s3_bucket.horde_storage[0].id : null
}

output "horde_storage_bucket_arn" {
  description = "ARN of the S3 bucket used for Horde artifact and log storage."
  value       = var.create_s3_storage_bucket ? aws_s3_bucket.horde_storage[0].arn : null
}

output "mongo_password_secret_arn" {
  description = "Secrets Manager ARN holding the MongoDB root password used by the Horde host."
  value       = aws_secretsmanager_secret.mongo.arn
}
