########################################
# GENERAL
########################################

variable "name" {
  type        = string
  description = "Name attached to Unreal Engine Horde module resources."
  default     = "unreal-horde"

  validation {
    condition     = length(var.name) > 1 && length(var.name) <= 50
    error_message = "name length must be between 2 and 50 characters."
  }
}

variable "project_prefix" {
  type        = string
  description = "Project prefix appended to most resource names."
  default     = "cgd"
}

variable "environment" {
  type        = string
  description = "Environment name (Development, Staging, Production). Sets ASPNETCORE_ENVIRONMENT and tags resources."
  default     = "Development"
}

variable "tags" {
  type = map(any)
  default = {
    "iac-management" = "CGD-Toolkit"
    "iac-module"     = "unreal-horde"
    "iac-provider"   = "Terraform"
  }
  description = "Tags to apply to resources."
}

variable "debug" {
  type        = bool
  description = "Enable debug helpers (forces redeploys, opens execute channels)."
  default     = false
}

########################################
# NETWORKING
########################################

variable "vpc_id" {
  type        = string
  description = "VPC ID where Horde resources are deployed."
}

variable "unreal_horde_service_subnets" {
  type        = list(string)
  description = "Subnets for the Horde EC2 host. The first subnet pins the host's AZ; the data EBS volume is created in that AZ."
  validation {
    condition     = length(var.unreal_horde_service_subnets) >= 1
    error_message = "At least one service subnet is required for the Horde host."
  }
}

variable "existing_security_groups" {
  type        = list(string)
  description = "Existing security group IDs to attach to the Horde host in addition to the module-managed SG."
  default     = []
}

variable "admin_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to SSH directly to the Horde host. Prefer SSM Session Manager (which needs no inbound rule)."
  default     = []
}

########################################
# HORDE SERVER HOST
########################################

variable "image" {
  type        = string
  description = "Horde server container image."
  default     = "ghcr.io/epicgames/horde-server:latest-bundled"
}

variable "horde_host_instance_type" {
  type        = string
  description = "EC2 instance type for the Horde all-in-one host. Must be amd64 (t3/t3a/m5/c5 families) - the Horde server image is amd64-only."
  default     = "t3.medium"
}

variable "horde_host_ami_id" {
  type        = string
  description = "AMI ID for the Horde host. If null, the most recent Amazon Linux 2023 arm64 AMI is used."
  default     = null
}

variable "horde_data_volume_size" {
  type        = number
  description = "Size in GiB of the EBS gp3 volume holding Mongo, Redis, and Horde server-side state."
  default     = 100
}

variable "mongo_username" {
  type        = string
  description = "MongoDB root username. Password is generated and stored in Secrets Manager."
  default     = "horde"
}

variable "mongo_max_cache_gb" {
  type        = string
  description = "WiredTiger cache size in GiB. Constrain on small hosts to keep Horde + Redis memory headroom."
  default     = "1.0"
}

variable "redis_maxmemory" {
  type        = string
  description = "Redis maxmemory directive (with units)."
  default     = "512mb"
}

variable "container_api_port" {
  type        = number
  description = "Host port for the Horde web server."
  default     = 5000
}

variable "container_grpc_port" {
  type        = number
  description = "Host port for the Horde gRPC (HTTP/2) channel. Matches Horde's standard Http2Port=8080 so agents and the dedicated ALB listener use the same port end-to-end."
  default     = 8080
}

variable "alb_https_ingress_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to reach the external Horde ALB on HTTPS (port 443). Defaults to 0.0.0.0/0 since the ALB terminates TLS and Horde handles auth."
  default     = ["0.0.0.0/0"]
}

variable "alb_grpc_ingress_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to reach the external Horde ALB on the gRPC port. Defaults to 0.0.0.0/0 so agents anywhere can enroll."
  default     = ["0.0.0.0/0"]
}

########################################
# LOAD BALANCING
########################################

variable "create_external_alb" {
  type        = bool
  description = "Create the external Application Load Balancer in front of the Horde host."
  default     = true
}

variable "unreal_horde_external_alb_subnets" {
  type        = list(string)
  description = "Subnets for the external Horde ALB. Two subnets in different AZs are required."
  default     = []
  validation {
    condition     = var.create_external_alb ? length(var.unreal_horde_external_alb_subnets) >= 2 : true
    error_message = "Provide at least two subnets in different AZs for the external ALB."
  }
}

variable "enable_unreal_horde_alb_access_logs" {
  type        = bool
  description = "Enable access logging for the Horde ALB."
  default     = false
}

variable "unreal_horde_alb_access_logs_bucket" {
  type        = string
  description = "Existing S3 bucket for ALB access logs. If null and logs are enabled, the module creates one."
  default     = null
}

variable "unreal_horde_alb_access_logs_prefix" {
  type        = string
  description = "Prefix for Horde ALB access logs."
  default     = null
}

variable "enable_unreal_horde_alb_deletion_protection" {
  type        = bool
  description = "Enable deletion protection on the Horde ALB."
  default     = false
}

variable "certificate_arn" {
  type        = string
  description = "ACM certificate ARN for the Horde HTTPS listener."
}

########################################
# IAM
########################################

variable "custom_unreal_horde_role" {
  type        = string
  description = "ARN of a custom IAM role to use for the Horde host (overrides the module-managed role)."
  default     = null
}

variable "create_unreal_horde_default_role" {
  type        = bool
  description = "Create the module-managed Horde host IAM role."
  default     = true
}

variable "create_unreal_horde_default_policy" {
  type        = bool
  description = "Attach the default SSM policy to the Horde host role."
  default     = true
}

variable "create_unreal_horde_recycle_policy" {
  type        = bool
  description = "Attach permissions for Horde's AwsAsg fleet manager to drive agent ASG scaling."
  default     = true

  validation {
    condition     = var.create_unreal_horde_recycle_policy == false || var.create_unreal_horde_default_role == true
    error_message = "Cannot create recycle policy without the default role."
  }
}

variable "github_credentials_secret_arn" {
  type        = string
  description = "Secrets Manager secret containing GitHub credentials with read:packages on the EpicGames org. Required to pull the Horde server image from ghcr.io."
  default     = null
}

########################################
# STORAGE (S3)
########################################

variable "create_s3_storage_bucket" {
  type        = bool
  description = "Create an S3 bucket used as Horde's artifact and log storage backend."
  default     = true
}

variable "s3_force_destroy" {
  type        = bool
  description = "Allow Terraform to destroy the S3 storage bucket even if it has objects. Set true only in non-production."
  default     = false
}

variable "s3_artifact_transition_ia_days" {
  type        = number
  description = "Days after which artifacts transition to S3 Standard-IA. AWS requires this to be at least 30 days for the STANDARD_IA storage class."
  default     = 30
  validation {
    condition     = var.s3_artifact_transition_ia_days >= 30
    error_message = "s3_artifact_transition_ia_days must be >= 30 (AWS STANDARD_IA minimum)."
  }
}

variable "s3_artifact_transition_glacier_days" {
  type        = number
  description = "Days after which artifacts transition to Glacier Instant Retrieval. Must be >= 30 days after the IA transition (so >= 60 by default) for AWS to accept the lifecycle policy."
  default     = 60
}

variable "s3_artifact_expiration_days" {
  type        = number
  description = "Days after which artifacts are permanently expired."
  default     = 90
}

variable "s3_log_expiration_days" {
  type        = number
  description = "Days after which Horde logs are permanently expired."
  default     = 30
}

########################################
# PERFORCE WIRING
########################################

variable "p4_port" {
  type        = string
  description = "Perforce server URL Horde should connect to (e.g. ssl:p4.studio.example.com:1666)."
  default     = null
}

variable "p4_super_user_username_secret_arn" {
  type        = string
  description = "Secrets Manager ARN for the p4d super-user username Horde uses as its service account."
  default     = null

  validation {
    condition     = var.p4_super_user_username_secret_arn == null || var.p4_port != null
    error_message = "Set p4_port when providing p4_super_user_username_secret_arn."
  }
}

variable "p4_super_user_password_secret_arn" {
  type        = string
  description = "Secrets Manager ARN for the p4d super-user password Horde uses as its service account."
  default     = null

  validation {
    condition     = var.p4_super_user_password_secret_arn == null || var.p4_port != null
    error_message = "Set p4_port when providing p4_super_user_password_secret_arn."
  }

  validation {
    condition     = (var.p4_super_user_username_secret_arn == null) == (var.p4_super_user_password_secret_arn == null)
    error_message = "p4_super_user_username_secret_arn and p4_super_user_password_secret_arn must be provided together."
  }
}

########################################
# AUTH (OIDC)
########################################

variable "auth_method" {
  type        = string
  description = "Authentication method for the Horde server."
  default     = null
  validation {
    condition     = var.auth_method == null || contains(["Anonymous", "Okta", "OpenIdConnect", "Horde"], var.auth_method)
    error_message = "Invalid authentication method. Must be one of: Anonymous, Okta, OpenIdConnect, Horde."
  }
}

variable "oidc_authority" {
  type    = string
  default = null
  validation {
    condition     = var.auth_method != null && contains(["Okta", "OpenIdConnect"], var.auth_method) ? var.oidc_authority != null : var.oidc_authority == null
    error_message = "oidc_authority is required for Okta and OpenIdConnect."
  }
  description = "OIDC authority URL."
}

variable "oidc_audience" {
  type    = string
  default = null
  validation {
    condition     = var.auth_method != null && contains(["Okta", "OpenIdConnect"], var.auth_method) ? var.oidc_audience != null : var.oidc_audience == null
    error_message = "oidc_audience is required for Okta and OpenIdConnect."
  }
  description = "OIDC audience."
}

variable "oidc_client_id" {
  type    = string
  default = null
  validation {
    condition     = var.auth_method != null && contains(["Okta", "OpenIdConnect"], var.auth_method) ? var.oidc_client_id != null : var.oidc_client_id == null
    error_message = "oidc_client_id is required for Okta and OpenIdConnect."
  }
  description = "OIDC client ID."
}

variable "oidc_client_secret" {
  type    = string
  default = null
  validation {
    condition     = var.auth_method != null && contains(["Okta", "OpenIdConnect"], var.auth_method) ? var.oidc_client_secret != null : var.oidc_client_secret == null
    error_message = "oidc_client_secret is required for Okta and OpenIdConnect."
  }
  description = "OIDC client secret."
}

variable "oidc_signin_redirect" {
  type    = string
  default = null
  validation {
    condition     = var.auth_method != null && contains(["Okta", "OpenIdConnect"], var.auth_method) ? var.oidc_signin_redirect != null : var.oidc_signin_redirect == null
    error_message = "oidc_signin_redirect is required for Okta and OpenIdConnect."
  }
  description = "OIDC sign-in redirect URL."
}

variable "admin_claim_type" {
  type        = string
  description = "Claim type for administrators."
  default     = null
}

variable "admin_claim_value" {
  type        = string
  description = "Claim value for administrators."
  default     = null
}

########################################
# BUILD AGENTS
########################################

variable "agents" {
  type = map(object({
    ami                                      = string
    instance_types                           = list(string)
    horde_pool_name                          = optional(string)
    create_asg                               = optional(bool, true)
    on_demand_base_capacity                  = optional(number, 0)
    on_demand_percentage_above_base_capacity = optional(number, 0)
    spot_allocation_strategy                 = optional(string, "capacity-optimized")
    block_device_mappings = list(object({
      device_name = string
      ebs = object({
        volume_size = number
        volume_type = optional(string, "gp3")
        iops        = optional(number)
        throughput  = optional(number)
      })
    }))
    min_size = optional(number, 0)
    max_size = optional(number, 1)
  }))
  description = "Map of agent pools. Each entry becomes an ASG using mixed_instances_policy across instance_types. Default behavior is 100% Spot, capacity-optimized."
  default     = {}
}

variable "agent_dotnet_runtime_version" {
  type        = string
  description = "dotnet-runtime version installed on Linux agents (match your engine release notes)."
  default     = "6.0"
}

variable "fully_qualified_domain_name" {
  type        = string
  description = "FQDN where Horde will be reachable. Agents enroll against this."
}

variable "enable_new_agents_by_default" {
  type        = bool
  description = "Auto-enable agents on first enrollment."
  default     = false
}

########################################
# HORDE CONFIG / TELEMETRY
########################################

variable "horde_config_path" {
  type        = string
  description = "Path to globals.json. Typically a P4 path under the Default cluster (e.g. //UE5/AgeOfTyrants/AgeOfTyrants/Build/Horde/globals.json) so the rest of the Horde config lives in source control. Null disables the env var (Horde runs without a config path)."
  default     = null
}

variable "horde_server_url" {
  type        = string
  description = "Public URL for the Horde server. Sets Horde__ServerUrl and Horde__DashboardUrl. If null, derived from fully_qualified_domain_name as https://<fqdn>."
  default     = null
}

variable "use_local_perforce_env" {
  type        = bool
  description = "Whether Horde reads P4 settings from the host's P4CONFIG/P4 env. Set false when Perforce wiring comes from module env vars and Secrets Manager."
  default     = true
}

variable "telemetry_type" {
  type        = string
  description = "Backend used by Horde's telemetry plugin (per-server-config Telemetry[0].Type)."
  default     = null
  validation {
    condition     = var.telemetry_type == null || contains(["Mongo", "Null", "ClickHouse"], var.telemetry_type)
    error_message = "telemetry_type must be one of: Mongo, Null, ClickHouse."
  }
}

variable "telemetry_retain_days" {
  type        = number
  description = "Days of telemetry data to retain (Telemetry[0].RetainDays)."
  default     = null
}
