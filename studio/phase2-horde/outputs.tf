output "horde_url" {
  description = "URL where the Horde web UI is reachable."
  value       = "https://horde.${var.route53_subdomain_zone_name}"
}

output "horde_host_instance_id" {
  description = "EC2 instance ID of the Horde host (use with SSM Session Manager)."
  value       = module.horde.horde_host_instance_id
}

output "horde_host_private_ip" {
  description = "Private IP of the Horde host."
  value       = module.horde.horde_host_private_ip
}

output "horde_storage_bucket_name" {
  description = "S3 bucket holding Horde artifacts and logs."
  value       = module.horde.horde_storage_bucket_name
}

output "horde_mongo_password_secret_arn" {
  description = "Secrets Manager ARN with the Mongo root password (in case you need to docker exec into the container)."
  value       = module.horde.mongo_password_secret_arn
}

output "horde_agent_security_group_id" {
  description = "Security group attached to Horde agent ASG instances."
  value       = module.horde.agent_security_group_id
}
