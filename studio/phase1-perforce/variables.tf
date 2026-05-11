variable "aws_region" {
  description = "AWS region for the Sidewinder Phase 1 deployment."
  type        = string
  default     = "us-east-1"
}

variable "route53_subdomain_zone_name" {
  description = "Name of the Route53 public hosted zone delegated for studio infrastructure (e.g. studio.sidewinder.dev)."
  type        = string
  default     = "studio.sidewinder.dev"
}

variable "allowed_p4_cidrs" {
  description = "CIDR blocks allowed to reach the P4 server on TCP/1666. Provide one /32 per developer."
  type        = list(string)
  default     = []
  validation {
    condition     = length(var.allowed_p4_cidrs) > 0
    error_message = "Supply at least one CIDR in allowed_p4_cidrs so the P4 server is reachable."
  }
}

variable "p4_depot_volume_size" {
  description = "Size in GiB for the P4 depot EBS volume."
  type        = number
  default     = 500
}

variable "p4_metadata_volume_size" {
  description = "Size in GiB for the P4 metadata EBS volume."
  type        = number
  default     = 32
}

variable "p4_logs_volume_size" {
  description = "Size in GiB for the P4 logs EBS volume."
  type        = number
  default     = 32
}

variable "p4_instance_type" {
  description = "EC2 instance type for the P4 server. Must match instance_architecture."
  type        = string
  default     = "t4g.medium"
}

variable "tags" {
  description = "Tags applied to all Sidewinder resources."
  type        = map(string)
  default = {
    Studio  = "Sidewinder"
    Project = "phase1-perforce"
  }
}

##############################################################################
# Tailscale subnet router (additive, replaces IP whitelist after cutover)
##############################################################################

variable "create_tailscale_relay" {
  description = "Whether to deploy the Tailscale subnet router in the studio VPC."
  type        = bool
  default     = true
}

variable "tailscale_auth_key_secret_name" {
  description = "Name (not ARN) of an AWS Secrets Manager secret holding a Tailscale auth key (tskey-auth-...). Must be created manually before apply."
  type        = string
  default     = "sidewinder/tailscale-auth-key"
}

variable "tailscale_relay_instance_type" {
  description = "EC2 instance type for the Tailscale subnet router. t4g.nano is plenty for a 5-person studio."
  type        = string
  default     = "t4g.nano"
}

variable "tailscale_relay_hostname" {
  description = "Hostname the subnet router advertises to the tailnet."
  type        = string
  default     = "sidewinder-aws-relay"
}

variable "tailscale_advertise_routes" {
  description = "Comma-separated list of CIDRs the relay advertises to the tailnet. Must match the studio VPC CIDR."
  type        = string
  default     = "10.40.0.0/16"
}

variable "tailscale_relay_tags" {
  description = "Comma-separated tailnet tags the relay node is assigned. Must be owned by the auth key. The autoApprover ACL keys off these."
  type        = string
  default     = "tag:subnet-router"
}

variable "tailscale_relay_enable_ssh" {
  description = "Enable Tailscale SSH on the relay so tailnet admins can SSH in via WireGuard identity (no SSH keys needed)."
  type        = bool
  default     = true
}
