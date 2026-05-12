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

variable "github_namespace" {
  description = "GitHub org or user that owns the repository."
  type        = string
  default     = "SidewinderGames"
}

variable "github_app_installation_id" {
  description = "Spacelift integration ID for the custom GitHub App (sidewinder-github). Find it in the Spacelift UI under Source code -> GitHub -> click the integration -> the Integration ID is shown on the details page (also visible in the URL). Required because the account has a named custom integration rather than the global default GitHub App."
  type        = string
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
  description = "AMI ID for the Linux Horde build agents. Ubuntu Noble amd64 works for first deploy; eventually a warm AMI with the project pre-synced."
  type        = string
}

variable "windows_agent_ami_id" {
  description = "AMI ID for the Windows Horde build agents. Built via assets/packer/build-agents/windows/windows.pkr.hcl. Empty string disables the Windows pool entirely."
  type        = string
  default     = ""
}

variable "space_id" {
  description = "Spacelift space the stacks live in."
  type        = string
  default     = "root"
}
