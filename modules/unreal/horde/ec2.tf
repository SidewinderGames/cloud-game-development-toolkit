data "aws_ami" "horde_host" {
  most_recent = true
  owners      = ["amazon"]

  # Horde server image (ghcr.io/epicgames/horde-server:*-bundled) is published
  # linux/amd64 only, so the host must be amd64. Pinning to t4g/Graviton AMIs
  # here would CrashLoop the container with "exec /usr/bin/dotnet: exec
  # format error". Keep instance_types in line with this (t3/t3a/m5).
  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_secretsmanager_secret" "mongo" {
  name                    = "${local.name_prefix}-mongo-password-${random_string.unreal_horde.result}"
  description             = "MongoDB password for the all-in-one Horde host"
  recovery_window_in_days = 0
  tags                    = local.tags
}

resource "aws_secretsmanager_secret_version" "mongo" {
  secret_id     = aws_secretsmanager_secret.mongo.id
  secret_string = random_password.mongo.result
}

data "aws_subnet" "horde_host" {
  id = var.unreal_horde_service_subnets[0]
}

resource "aws_ebs_volume" "horde_data" {
  availability_zone = data.aws_subnet.horde_host.availability_zone
  size              = var.horde_data_volume_size
  type              = "gp3"
  encrypted         = true

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-data"
  })
}

resource "aws_volume_attachment" "horde_data" {
  device_name  = "/dev/sdf"
  volume_id    = aws_ebs_volume.horde_data.id
  instance_id  = aws_instance.horde_host.id
  force_detach = true
}

resource "aws_instance" "horde_host" {
  ami                         = coalesce(var.horde_host_ami_id, data.aws_ami.horde_host.id)
  instance_type               = var.horde_host_instance_type
  subnet_id                   = var.unreal_horde_service_subnets[0]
  vpc_security_group_ids      = concat([aws_security_group.unreal_horde_sg.id], var.existing_security_groups)
  iam_instance_profile        = aws_iam_instance_profile.horde_host.name
  associate_public_ip_address = true
  ebs_optimized               = true
  monitoring                  = true

  root_block_device {
    encrypted             = true
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }

  user_data = base64encode(templatefile("${path.module}/templates/horde_host_user_data.sh.tftpl", {
    region                            = data.aws_region.current.id
    ghcr_credentials_secret_arn       = var.github_credentials_secret_arn == null ? "" : var.github_credentials_secret_arn
    mongo_username                    = var.mongo_username
    mongo_password_secret_arn         = aws_secretsmanager_secret.mongo.arn
    p4_super_user_username_secret_arn = var.p4_super_user_username_secret_arn == null ? "" : var.p4_super_user_username_secret_arn
    p4_super_user_password_secret_arn = var.p4_super_user_password_secret_arn == null ? "" : var.p4_super_user_password_secret_arn
    p4_port                           = var.p4_port == null ? "" : var.p4_port
    fqdn                              = var.fully_qualified_domain_name
    api_port                          = var.container_api_port
    grpc_port                         = var.container_grpc_port
    horde_image                       = var.image
    mongo_max_cache_gb                = var.mongo_max_cache_gb
    redis_maxmemory                   = var.redis_maxmemory
    horde_env_lines                   = join("\n", [for e in local.horde_service_env : "${e.name}=${e.value}"])
    docker_compose_yaml = templatefile("${path.module}/templates/docker-compose.yml.tftpl", {
      horde_image        = var.image
      api_port           = var.container_api_port
      grpc_port          = var.container_grpc_port
      mongo_max_cache_gb = var.mongo_max_cache_gb
      redis_maxmemory    = var.redis_maxmemory
    })
  }))

  user_data_replace_on_change = false

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-host"
  })

  lifecycle {
    ignore_changes = [ami]
  }
}
