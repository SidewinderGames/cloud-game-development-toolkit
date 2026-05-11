variable "vcs_repository" {
  description = "Repository name as registered with the Spacelift GitHub App. The org/owner is implicit in the integration."
  type        = string
  default     = "cloud-game-development-toolkit"
}

variable "vcs_branch" {
  description = "Branch the stacks track."
  type        = string
  default     = "sidewinder"
}

variable "terraform_version" {
  description = "OpenTofu version used by the runners. OpenTofu is the open-source fork of pre-BSL Terraform; wire-compatible with all our providers."
  type        = string
  default     = "1.10.6"
}

variable "aws_runner_role_arn" {
  description = "ARN of the IAM role from spacelift-bootstrap that Spacelift's runners assume via OIDC."
  type        = string
}

variable "aws_region" {
  description = "AWS region the stacks deploy into."
  type        = string
  default     = "us-east-1"
}

variable "route53_subdomain_zone_name" {
  description = "Delegated Route53 zone (Phase 1 creates this name pattern)."
  type        = string
  default     = "studio.sidewinder.dev"
}

variable "allowed_p4_cidrs" {
  description = "JSON-encoded list of CIDR blocks allowed to reach P4 on TCP/1666."
  type        = string
  default     = "[]"
}

variable "github_credentials_secret_arn" {
  description = "Secrets Manager ARN holding GHCR credentials (ghcr.io PAT for the Epic Games org). Used by Phase 2 only."
  type        = string
}

variable "agent_ami_id" {
  description = "AMI ID for Horde build agents."
  type        = string
}

variable "space_id" {
  description = "Spacelift space the stacks live in."
  type        = string
  default     = "root"
}
