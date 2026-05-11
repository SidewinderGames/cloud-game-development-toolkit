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
