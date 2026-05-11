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
    {
      name  = "Horde__enableNewAgentsByDefault",
      value = tostring(var.enable_new_agents_by_default)
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
  ] : config.value != null ? config : null]

  horde_service_secrets = {
    p4_super_username = var.p4_super_user_username_secret_arn
    p4_super_password = var.p4_super_user_password_secret_arn
  }
}
