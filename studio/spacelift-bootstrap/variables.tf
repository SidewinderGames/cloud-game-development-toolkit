variable "aws_region" {
  description = "AWS region for the IAM resources. IAM is global so this only affects provider behavior."
  type        = string
  default     = "us-east-1"
}

variable "spacelift_account_name" {
  description = "Spacelift account subdomain (e.g. sidewinder-games for sidewinder-games.app.us.spacelift.io)."
  type        = string
  default     = "sidewinder-games"
}

variable "spacelift_account_region" {
  description = "Regional segment in the Spacelift URL. Set to 'us' for sidewinder-games.app.us.spacelift.io, 'eu' for the EU region, or empty string for legacy accounts without a region segment."
  type        = string
  default     = "us"

  validation {
    condition     = contains(["", "us", "eu"], var.spacelift_account_region)
    error_message = "spacelift_account_region must be empty, 'us', or 'eu'."
  }
}

variable "spacelift_space_id" {
  description = "Spacelift space the stacks live in. Defaults to the root space."
  type        = string
  default     = "root"
}

variable "managed_stack_slugs" {
  description = "Stack slugs whose runs are allowed to assume the IAM role. The OIDC subject claim is built from these."
  type        = list(string)
  default = [
    "sidewinder-phase1-perforce",
    "sidewinder-phase2-horde",
  ]
}

variable "iam_role_name" {
  description = "Name for the IAM role Spacelift assumes."
  type        = string
  default     = "sidewinder-spacelift-runner"
}

variable "tags" {
  description = "Tags applied to bootstrap resources."
  type        = map(string)
  default = {
    Studio  = "Sidewinder"
    Project = "spacelift-bootstrap"
  }
}
