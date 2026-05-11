data "aws_availability_zones" "available" {}

locals {
  vpc_cidr_block       = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.3.0/24", "10.0.4.0/24"]
  azs                  = slice(data.aws_availability_zones.available.names, 0, 2)
  tags                 = {}
}

module "unreal_engine_horde" {
  source                            = "../../"
  vpc_id                            = aws_vpc.unreal_engine_horde_vpc.id
  unreal_horde_service_subnets      = aws_subnet.private_subnets[*].id
  unreal_horde_external_alb_subnets = aws_subnet.public_subnets[*].id
  certificate_arn                   = aws_acm_certificate.unreal_engine_horde.arn
  github_credentials_secret_arn     = var.github_credentials_secret_arn
  tags                              = local.tags

  horde_host_instance_type = "t4g.medium"
  horde_data_volume_size   = 100

  fully_qualified_domain_name = "horde.${var.root_domain_name}"

  agents = {
    linux-ue-builder = {
      ami                                      = data.aws_ami.ubuntu_noble_amd.id
      instance_types                           = ["c7a.xlarge", "c7i.xlarge", "c6a.xlarge"]
      horde_pool_name                          = "linux-ue-builder"
      on_demand_base_capacity                  = 0
      on_demand_percentage_above_base_capacity = 0
      spot_allocation_strategy                 = "capacity-optimized"
      min_size                                 = 0
      max_size                                 = 5
      block_device_mappings = [
        {
          device_name = "/dev/sda1"
          ebs = {
            volume_size = 1024
            volume_type = "gp3"
          }
        }
      ]
    }
  }

  depends_on = [aws_acm_certificate_validation.unreal_engine_horde]
}
