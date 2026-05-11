variable "aws_region" {
  description = "AWS region. Must match Phase 1."
  type        = string
  default     = "us-east-1"
}

variable "route53_subdomain_zone_name" {
  description = "Delegated Route53 zone name (must match Phase 1)."
  type        = string
  default     = "studio.sidewinder.dev"
}

variable "github_credentials_secret_arn" {
  description = "Secrets Manager ARN with GitHub credentials (read:packages on the EpicGames org) for ghcr.io image pulls. Create this manually before applying."
  type        = string
}

variable "p4_super_user_username_secret_arn" {
  description = "Secrets Manager ARN for the p4d super-user username. Copy from Phase 1's p4_admin_username_secret_arn output (or use the dedicated super secret if you created a separate Horde service account)."
  type        = string
}

variable "p4_super_user_password_secret_arn" {
  description = "Secrets Manager ARN for the p4d super-user password. Copy from Phase 1's p4_super_password_secret_arn output."
  type        = string
}

variable "admin_cidrs" {
  description = "CIDR blocks allowed to SSH directly to the Horde host. Defaults to empty; use SSM Session Manager instead."
  type        = list(string)
  default     = []
}

variable "horde_host_instance_type" {
  description = "EC2 instance type for the Horde all-in-one host."
  type        = string
  default     = "t4g.medium"
}

variable "horde_data_volume_size" {
  description = "Size in GiB of the Horde data EBS volume (Mongo, Redis, server state)."
  type        = number
  default     = 100
}

variable "agent_ami_id" {
  description = "AMI ID for the build agent ASG. Use a Linux AMI with the Horde agent prerequisites baked in, or supply a freshly built agent AMI. The example uses an Ubuntu 24.04 base."
  type        = string
}

variable "agent_max_size" {
  description = "Maximum number of Spot build agents to launch concurrently."
  type        = number
  default     = 3
}

variable "agent_workspace_size_gib" {
  description = "Size in GiB of each Spot agent's workspace volume (for cloning the UE project)."
  type        = number
  default     = 1024
}

variable "agent_pool_name" {
  description = "Horde pool name and the value of the Horde_Autoscale_Pool tag the AwsAsg fleet manager will use to find this ASG."
  type        = string
  default     = "linux-ue-builder"
}

variable "tags" {
  description = "Tags applied to all Phase 2 resources."
  type        = map(string)
  default = {
    Studio  = "Sidewinder"
    Project = "phase2-horde"
  }
}
