module "perforce" {
  source = "../../modules/perforce"

  project_prefix = local.project_prefix
  vpc_id         = aws_vpc.studio.id

  create_shared_network_load_balancer     = false
  create_shared_application_load_balancer = false
  create_route53_private_hosted_zone      = false

  certificate_arn = aws_acm_certificate_validation.studio_wildcard.certificate_arn

  p4_auth_config        = null
  p4_code_review_config = null

  p4_server_config = {
    name                        = "p4-server"
    fully_qualified_domain_name = local.p4_server_fqdn
    p4_server_type              = "p4d_commit"

    lookup_existing_ami   = true
    ami_prefix            = "p4_al2023"
    instance_type         = var.p4_instance_type
    instance_architecture = "arm64"

    storage_type         = "EBS"
    depot_volume_size    = var.p4_depot_volume_size
    metadata_volume_size = var.p4_metadata_volume_size
    logs_volume_size     = var.p4_logs_volume_size

    unicode        = false
    selinux        = false
    case_sensitive = true
    plaintext      = false

    instance_subnet_id       = aws_subnet.public[0].id
    internal                 = false
    create_default_sg        = true
    existing_security_groups = [aws_security_group.p4_user_access.id]
  }

  tags = var.tags

  depends_on = [aws_internet_gateway.igw]
}

provider "netapp-ontap" {
  connection_profiles = [
    {
      name     = "null"
      hostname = "null"
      username = "null"
      password = "null"
    }
  ]
}
