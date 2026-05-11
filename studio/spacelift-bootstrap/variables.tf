variable "aws_region" {
  description = "AWS region for the IAM resources. IAM is global so this only affects provider behavior."
  type        = string
  default     = "us-east-1"
}

variable "spacelift_account_name" {
  description = "Spacelift account subdomain (e.g. sidewinder-games for sidewinder-games.app.us.spacelift.io). Used as the external-id prefix in the IAM role's trust policy."
  type        = string
  default     = "sidewinder-games"
}

variable "spacelift_account_region" {
  description = "Spacelift SaaS region the account lives in. Drives which Spacelift-owned AWS account principal to trust. 'us' for app.us.spacelift.io, '' for the default app.spacelift.io."
  type        = string
  default     = "us"

  validation {
    condition     = contains(["", "us"], var.spacelift_account_region)
    error_message = "spacelift_account_region must be '' or 'us'. Add a mapping in main.tf if Spacelift adds more regions."
  }
}

variable "spacelift_aws_principal_account_id_override" {
  description = "Optional override for the Spacelift-owned AWS account ID that's allowed to assume the role. If null, derived from spacelift_account_region."
  type        = string
  default     = null
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
