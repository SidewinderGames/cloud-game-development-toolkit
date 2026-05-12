###############################################################################
# AWS integration (one-time, shared by all Sidewinder stacks)
###############################################################################

resource "spacelift_aws_integration" "sidewinder" {
  name                           = "sidewinder-aws"
  role_arn                       = var.aws_runner_role_arn
  generate_credentials_in_worker = false
  space_id                       = var.space_id
  labels                         = ["sidewinder"]
}

###############################################################################
# Phase 1: Perforce
###############################################################################

resource "spacelift_stack" "phase1_perforce" {
  name                    = "Sidewinder Phase 1 - Perforce"
  description             = "P4 Server (Helix Core) deployment for Sidewinder Games."
  space_id                = var.space_id
  repository              = var.vcs_repository
  branch                  = var.vcs_branch
  project_root            = "studio/phase1-perforce"
  terraform_version       = var.terraform_version
  terraform_workflow_tool = "OPEN_TOFU"

  github_enterprise {
    namespace = var.github_namespace
    id        = var.github_app_installation_id
  }

  autodeploy            = false
  enable_local_preview  = false
  protect_from_deletion = true

  labels = ["sidewinder", "phase1", "perforce"]
}

resource "spacelift_aws_integration_attachment" "phase1" {
  integration_id = spacelift_aws_integration.sidewinder.id
  stack_id       = spacelift_stack.phase1_perforce.id
  read           = true
  write          = true
}

resource "spacelift_environment_variable" "phase1_aws_region" {
  stack_id   = spacelift_stack.phase1_perforce.id
  name       = "AWS_DEFAULT_REGION"
  value      = var.aws_region
  write_only = false
}

resource "spacelift_environment_variable" "phase1_tf_aws_region" {
  stack_id   = spacelift_stack.phase1_perforce.id
  name       = "TF_VAR_aws_region"
  value      = var.aws_region
  write_only = false
}

resource "spacelift_environment_variable" "phase1_tf_zone" {
  stack_id   = spacelift_stack.phase1_perforce.id
  name       = "TF_VAR_route53_subdomain_zone_name"
  value      = var.route53_subdomain_zone_name
  write_only = false
}

resource "spacelift_environment_variable" "phase1_tf_cidrs" {
  stack_id   = spacelift_stack.phase1_perforce.id
  name       = "TF_VAR_allowed_p4_cidrs"
  value      = var.allowed_p4_cidrs
  write_only = false
}

###############################################################################
# Phase 2: Unreal Horde
###############################################################################

resource "spacelift_stack" "phase2_horde" {
  name                    = "Sidewinder Phase 2 - Horde"
  description             = "Unreal Horde all-in-one host plus Spot agent ASG."
  space_id                = var.space_id
  repository              = var.vcs_repository
  branch                  = var.vcs_branch
  project_root            = "studio/phase2-horde"
  terraform_version       = var.terraform_version
  terraform_workflow_tool = "OPEN_TOFU"

  github_enterprise {
    namespace = var.github_namespace
    id        = var.github_app_installation_id
  }

  autodeploy            = false
  enable_local_preview  = false
  protect_from_deletion = true

  labels = ["sidewinder", "phase2", "horde"]
}

resource "spacelift_aws_integration_attachment" "phase2" {
  integration_id = spacelift_aws_integration.sidewinder.id
  stack_id       = spacelift_stack.phase2_horde.id
  read           = true
  write          = true
}

resource "spacelift_environment_variable" "phase2_aws_region" {
  stack_id   = spacelift_stack.phase2_horde.id
  name       = "AWS_DEFAULT_REGION"
  value      = var.aws_region
  write_only = false
}

resource "spacelift_environment_variable" "phase2_tf_aws_region" {
  stack_id   = spacelift_stack.phase2_horde.id
  name       = "TF_VAR_aws_region"
  value      = var.aws_region
  write_only = false
}

resource "spacelift_environment_variable" "phase2_tf_zone" {
  stack_id   = spacelift_stack.phase2_horde.id
  name       = "TF_VAR_route53_subdomain_zone_name"
  value      = var.route53_subdomain_zone_name
  write_only = false
}

resource "spacelift_environment_variable" "phase2_tf_ghcr" {
  stack_id   = spacelift_stack.phase2_horde.id
  name       = "TF_VAR_github_credentials_secret_arn"
  value      = var.github_credentials_secret_arn
  write_only = false
}

resource "spacelift_environment_variable" "phase2_tf_agent_ami" {
  count      = var.agent_ami_id == "" ? 0 : 1
  stack_id   = spacelift_stack.phase2_horde.id
  name       = "TF_VAR_agent_ami_id"
  value      = var.agent_ami_id
  write_only = false
}

resource "spacelift_environment_variable" "phase2_tf_windows_agent_ami" {
  count      = var.windows_agent_ami_id == "" ? 0 : 1
  stack_id   = spacelift_stack.phase2_horde.id
  name       = "TF_VAR_windows_agent_ami_id"
  value      = var.windows_agent_ami_id
  write_only = false
}

###############################################################################
# Stack dependency: Phase 2 inherits Phase 1's outputs
###############################################################################

resource "spacelift_stack_dependency" "phase2_on_phase1" {
  stack_id            = spacelift_stack.phase2_horde.id
  depends_on_stack_id = spacelift_stack.phase1_perforce.id
}

resource "spacelift_stack_dependency_reference" "vpc_id" {
  stack_dependency_id = spacelift_stack_dependency.phase2_on_phase1.id
  output_name         = "studio_vpc_id"
  input_name          = "TF_VAR_vpc_id"
}

resource "spacelift_stack_dependency_reference" "public_subnets" {
  stack_dependency_id = spacelift_stack_dependency.phase2_on_phase1.id
  output_name         = "studio_public_subnet_ids"
  input_name          = "TF_VAR_public_subnet_ids"
}

resource "spacelift_stack_dependency_reference" "wildcard_cert" {
  stack_dependency_id = spacelift_stack_dependency.phase2_on_phase1.id
  output_name         = "studio_wildcard_certificate_arn"
  input_name          = "TF_VAR_certificate_arn"
}

resource "spacelift_stack_dependency_reference" "p4_super_username" {
  stack_dependency_id = spacelift_stack_dependency.phase2_on_phase1.id
  output_name         = "p4_admin_username_secret_arn"
  input_name          = "TF_VAR_p4_super_user_username_secret_arn"
}

resource "spacelift_stack_dependency_reference" "p4_super_password" {
  stack_dependency_id = spacelift_stack_dependency.phase2_on_phase1.id
  output_name         = "p4_super_password_secret_arn"
  input_name          = "TF_VAR_p4_super_user_password_secret_arn"
}
