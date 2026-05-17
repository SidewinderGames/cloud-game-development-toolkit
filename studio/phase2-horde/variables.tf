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
  description = "Secrets Manager ARN for the p4d super-user username. Spacelift feeds this from Phase 1's p4_admin_username_secret_arn output via stack dependency. Set manually if running locally."
  type        = string
}

variable "p4_super_user_password_secret_arn" {
  description = "Secrets Manager ARN for the p4d super-user password. Spacelift feeds this from Phase 1's p4_super_password_secret_arn output via stack dependency. Set manually if running locally."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID from Phase 1. Spacelift feeds this from Phase 1's studio_vpc_id output via stack dependency."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs from Phase 1. Spacelift feeds these from Phase 1's studio_public_subnet_ids output via stack dependency."
  type        = list(string)
  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "Phase 2 needs at least two public subnets in different AZs for the external ALB."
  }
}

variable "certificate_arn" {
  description = "Wildcard ACM cert ARN from Phase 1. Spacelift feeds this from Phase 1's studio_wildcard_certificate_arn output via stack dependency."
  type        = string
}

variable "admin_cidrs" {
  description = "CIDR blocks allowed to SSH directly to the Horde host. Defaults to empty; use SSM Session Manager instead."
  type        = list(string)
  default     = []
}

variable "horde_host_instance_type" {
  description = "EC2 instance type for the Horde all-in-one host. Must be amd64 (t3/t3a/m5/c5) - ghcr.io/epicgames/horde-server is amd64-only."
  type        = string
  default     = "t3.medium"
}

variable "horde_image_tag" {
  description = "Tag of the Horde Server image in the Sidewinder ECR repository. Bump after pushing a new build (e.g. \"5.7.4-datavol9\")."
  type        = string
  default     = "5.7.4-datavol9"
}

variable "horde_data_volume_size" {
  description = "Size in GiB of the Horde data EBS volume (Mongo, Redis, server state)."
  type        = number
  default     = 100
}

variable "agent_ami_id" {
  description = "AMI ID for the LINUX build agent ASG. Empty string disables the Linux pool entirely (Windows-only deploys are valid). Use a Linux AMI with the Horde agent prerequisites baked in (Ubuntu 24.04 base recommended)."
  type        = string
  default     = ""
}

variable "agent_max_size" {
  description = "Maximum number of Linux Spot build agents to launch concurrently."
  type        = number
  default     = 3
}

variable "agent_workspace_size_gib" {
  description = "Size in GiB of the Linux pool data volume (per AZ). Includes UE source + Setup.sh binaries + build intermediates."
  type        = number
  default     = 1024
}

variable "agent_data_volume_snapshot_id" {
  description = "Seed snapshot ID for the Linux pool's data volume. See windows_agent_data_volume_snapshot_id."
  type        = string
  default     = null
}

variable "agent_pool_name" {
  description = "Horde pool name and Horde_Autoscale_Pool tag value for the Linux pool."
  type        = string
  default     = "linux-ue-builder"
}

# Windows agent pool. Set windows_agent_ami_id to enable; leave empty to skip.

variable "windows_agent_ami_id" {
  description = "AMI ID for the WINDOWS build agent ASG. Built via assets/packer/build-agents/windows/windows.pkr.hcl. Empty string disables the Windows pool entirely (only Linux agents will run)."
  type        = string
  default     = ""
}

variable "windows_agent_min_size" {
  description = "Minimum always-running Windows agents. Defaults to 0; the AwsAsgWithDataVolumes fleet strategy attaches the pool's persistent EBS data volume on cold start, eliminating the need to keep an instance running."
  type        = number
  default     = 0
}

variable "windows_agent_max_size" {
  description = "Maximum number of Windows Spot build agents in service concurrently. Set to 1 during testing - JobQueue strategy will not scale out beyond this, so additional queued jobs wait. Raise to enable real autoscaling."
  type        = number
  default     = 1
}

variable "windows_agent_workspace_size_gib" {
  description = "Size in GiB of the Windows pool data volume (per AZ). Windows + UE source + Setup.bat binaries + build intermediates need >= 512 GiB; 1024 leaves room."
  type        = number
  default     = 1024
}

variable "windows_agent_data_volume_snapshot_id" {
  description = "Seed snapshot ID for the Windows pool's data volume. When a new instance launches in an AZ that has no free volume, the AwsAsgWithDataVolumes fleet strategy creates a fresh volume from this snapshot - skipping the cold P4 sync. Refresh periodically (see Engine/Source/Programs/Horde/Docs/Internals/AwsAsgWithDataVolumes.md). Leave null for the first deployment; the first launch creates an empty volume that pays a full sync once."
  type        = string
  default     = null
}

variable "windows_agent_pool_name" {
  description = "Horde pool name and Horde_Autoscale_Pool tag value for the Windows pool."
  type        = string
  default     = "windows-ue-builder"
}

variable "windows_agent_instance_types" {
  description = "Instance types the Windows ASG will request via mixed_instances_policy. Listed in priority order; spot capacity-optimized picks the cheapest currently available. During Horde testing we lead with c7a.xlarge spot (~$0.04/hr) so the always-warm agent is cheap; production should put compile-grade c7a.4xlarge / c7i.4xlarge first."
  type        = list(string)
  default     = ["c7a.xlarge", "m7a.xlarge", "c7i.xlarge", "c7a.2xlarge"]
}

variable "tags" {
  description = "Tags applied to all Phase 2 resources."
  type        = map(string)
  default = {
    Studio  = "Sidewinder"
    Project = "phase2-horde"
  }
}
