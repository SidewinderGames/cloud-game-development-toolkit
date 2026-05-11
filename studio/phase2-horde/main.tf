module "horde" {
  source = "../../modules/unreal/horde"

  project_prefix = "sidewinder"
  name           = "horde"
  environment    = "Production"

  vpc_id                            = var.vpc_id
  unreal_horde_service_subnets      = var.public_subnet_ids
  unreal_horde_external_alb_subnets = var.public_subnet_ids

  certificate_arn = var.certificate_arn

  horde_host_instance_type = var.horde_host_instance_type
  horde_data_volume_size   = var.horde_data_volume_size
  admin_cidrs              = var.admin_cidrs

  github_credentials_secret_arn = var.github_credentials_secret_arn
  fully_qualified_domain_name   = "horde.${var.route53_subdomain_zone_name}"

  p4_port                           = "ssl:p4.${var.route53_subdomain_zone_name}:1666"
  p4_super_user_username_secret_arn = var.p4_super_user_username_secret_arn
  p4_super_user_password_secret_arn = var.p4_super_user_password_secret_arn

  auth_method                  = "Anonymous"
  enable_new_agents_by_default = true

  create_unreal_horde_recycle_policy = true
  create_s3_storage_bucket           = true
  s3_force_destroy                   = false

  enable_unreal_horde_alb_access_logs = false

  agents = {
    (var.agent_pool_name) = {
      ami                                      = var.agent_ami_id
      instance_types                           = ["c7a.xlarge", "c7i.xlarge", "c6a.xlarge"]
      horde_pool_name                          = var.agent_pool_name
      on_demand_base_capacity                  = 0
      on_demand_percentage_above_base_capacity = 0
      spot_allocation_strategy                 = "capacity-optimized"
      min_size                                 = 0
      max_size                                 = var.agent_max_size
      block_device_mappings = [
        {
          device_name = "/dev/sda1"
          ebs = {
            volume_size = var.agent_workspace_size_gib
            volume_type = "gp3"
          }
        }
      ]
    }
  }

  tags = var.tags
}
