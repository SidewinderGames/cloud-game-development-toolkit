resource "random_string" "unreal_horde" {
  length  = 4
  special = false
  upper   = false
}

resource "random_password" "mongo" {
  length  = 32
  special = false
}

data "aws_region" "current" {}

locals {
  name_prefix = "${var.project_prefix}-${var.name}"
  tags = merge(var.tags, {
    "environment" = var.environment
  })

  database_connection_string = "mongodb://${var.mongo_username}:${random_password.mongo.result}@127.0.0.1:27017/?directConnection=true&readPreference=primary&retryWrites=true"
  redis_connection_config    = "127.0.0.1:6379"

  need_p4_trust = var.p4_port != null && startswith(var.p4_port, "ssl:")

  horde_service_env = [for config in [
    {
      name  = "Horde__authMethod"
      value = var.auth_method
    },
    {
      name  = "Horde__oidcAuthority"
      value = var.oidc_authority
    },
    {
      name  = "Horde__oidcAudience",
      value = var.oidc_audience
    },
    {
      name  = "Horde__oidcClientId"
      value = var.oidc_client_id
    },
    {
      name  = "Horde__oidcClientSecret"
      value = var.oidc_client_secret
    },
    {
      name  = "Horde__oidcSigninRedirect"
      value = var.oidc_signin_redirect
    },
    {
      name  = "Horde__adminClaimType"
      value = var.admin_claim_type
    },
    {
      name  = "Horde__adminClaimValue"
      value = var.admin_claim_value
    },
    # NOTE: Horde__enableNewAgentsByDefault is defined in ServerSettings.cs
    # but unused anywhere in the codebase. The real auto-approve flag is
    # Horde:Plugins:Compute:AutoEnrollAgents, wired below. Without it, every
    # agent that registers sits in Agent Enrollment waiting for a human to
    # click "Approve" - fine for static fleets, broken for ASGs.
    {
      name  = "Horde__Plugins__Compute__AutoEnrollAgents"
      value = tostring(var.auto_enroll_agents)
    },
    {
      name  = "Horde__Perforce__0__ServerAndPort"
      value = var.p4_port
    },
    {
      name  = "ASPNETCORE_ENVIRONMENT"
      value = var.environment
    },
    {
      name  = "Horde__Plugins__Storage__Backend__Type"
      value = var.create_s3_storage_bucket ? "Aws" : null
    },
    {
      name  = "Horde__Plugins__Storage__Backend__AwsBucketName"
      value = var.create_s3_storage_bucket ? aws_s3_bucket.horde_storage[0].id : null
    },
    {
      name  = "Horde__Plugins__Storage__Backend__AwsBucketPath"
      value = var.create_s3_storage_bucket ? "horde/" : null
    },
    {
      name  = "Horde__Plugins__Storage__Backend__AwsRegion"
      value = var.create_s3_storage_bucket ? data.aws_region.current.id : null
    },
    {
      name  = "Horde__Plugins__Compute__WithAws"
      value = length(var.agents) > 0 ? "true" : null
    },
    {
      name  = "Horde__Plugins__Compute__AwsRegions__0"
      value = length(var.agents) > 0 ? data.aws_region.current.id : null
    },
    # SQS queue the Horde server polls for ASG lifecycle events (used by the
    # AwsAsgWithDataVolumes fleet strategy for launch-attach / terminate-detach
    # of pool data volumes). Only set when there are agent pools.
    {
      name  = "Horde__Plugins__Compute__AwsAutoScalingQueueUrls__0"
      value = length(var.agents) > 0 ? aws_sqs_queue.asg_lifecycle[0].url : null
    },
    # Tell the Horde server's P4 client where to find its trust file. The
    # horde container mounts /var/lib/horde-data/horde at /app/Data, and the
    # user-data writes the trust file there (both DNS-form and IP-form
    # entries so SSL connections via p4.studio.sidewinder.dev or the private
    # IP both verify). Without this, the P4 client falls back to ~/.p4trust
    # which isn't populated, and every cluster health check fails with
    # "authenticity of host can't be established".
    {
      name  = "P4TRUST"
      value = var.p4_port != null ? "/app/Data/.p4trust" : null
    },
    {
      name  = "Horde__ServerUrl"
      value = var.horde_server_url != null ? var.horde_server_url : "https://${var.fully_qualified_domain_name}"
    },
    {
      name  = "Horde__DashboardUrl"
      value = var.horde_server_url != null ? var.horde_server_url : "https://${var.fully_qualified_domain_name}"
    },
    {
      name  = "Horde__ConfigPath"
      value = var.horde_config_path
    },
    {
      name  = "Horde__Perforce__0__Id"
      value = var.p4_port != null ? "Default" : null
    },
    {
      name  = "Horde__UseLocalPerforceEnv"
      value = tostring(var.use_local_perforce_env)
    },
    {
      name  = "Horde__Telemetry__0__Type"
      value = var.telemetry_type
    },
    {
      name  = "Horde__Telemetry__0__RetainDays"
      value = var.telemetry_retain_days != null ? tostring(var.telemetry_retain_days) : null
    },
  ] : config if config.value != null]

  horde_service_secrets = {
    p4_super_username = var.p4_super_user_username_secret_arn
    p4_super_password = var.p4_super_user_password_secret_arn
  }
}
