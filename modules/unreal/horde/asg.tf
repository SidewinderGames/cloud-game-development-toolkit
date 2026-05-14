locals {
  unreal_horde_agent_userdata_windows = base64encode(templatefile("${path.module}/config/agent/agent-config.ps1", {
    p4_trust_bucket             = local.need_p4_trust && length(var.agents) > 0 ? aws_s3_bucket.ansible_playbooks[0].id : null
    fully_qualified_domain_name = var.fully_qualified_domain_name
    dotnet_runtime_version      = var.agent_dotnet_runtime_version
  }))
}

data "aws_ami" "unreal_horde_agent_ami" {
  for_each = var.agents

  most_recent = true

  filter {
    name   = "image-id"
    values = [each.value.ami]
  }
}

resource "aws_launch_template" "unreal_horde_agent_template" {
  for_each    = var.agents
  name_prefix = "unreal_horde_agent-${each.key}"
  description = "Launch template for ${each.key} Unreal Horde Agents"

  image_id      = each.value.ami
  ebs_optimized = true

  dynamic "block_device_mappings" {
    for_each = each.value.block_device_mappings
    content {
      device_name = block_device_mappings.value.device_name
      ebs {
        volume_size           = block_device_mappings.value.ebs.volume_size
        volume_type           = try(block_device_mappings.value.ebs.volume_type, "gp3")
        iops                  = try(block_device_mappings.value.ebs.iops, null)
        throughput            = try(block_device_mappings.value.ebs.throughput, null)
        encrypted             = true
        delete_on_termination = true
      }
    }
  }

  user_data = data.aws_ami.unreal_horde_agent_ami[each.key].platform == "windows" ? local.unreal_horde_agent_userdata_windows : null

  vpc_security_group_ids = [aws_security_group.unreal_horde_agent_sg[0].id]

  private_dns_name_options {
    hostname_type = "resource-name"
  }
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }
  iam_instance_profile {
    arn = aws_iam_instance_profile.unreal_horde_agent_instance_profile[0].arn
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      {
        Name = "${each.key} Horde Agent"
      },
      each.value.horde_pool_name != null ? {
        Horde_Autoscale_Pool   = each.value.horde_pool_name
        Horde_Autoscale_PoolId = each.value.horde_pool_name
      } : {},
    )
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name = "${each.key} Horde Agent workspace"
    }
  }
}

resource "aws_autoscaling_group" "unreal_horde_agent_asg" {
  for_each    = { for k, v in var.agents : k => v if v.create_asg }
  name_prefix = "unreal_horde_agents-${each.key}-"

  vpc_zone_identifier = var.unreal_horde_service_subnets

  min_size         = each.value.min_size
  max_size         = each.value.max_size
  desired_capacity = each.value.min_size

  capacity_rebalance = true

  mixed_instances_policy {
    instances_distribution {
      on_demand_base_capacity                  = each.value.on_demand_base_capacity
      on_demand_percentage_above_base_capacity = each.value.on_demand_percentage_above_base_capacity
      spot_allocation_strategy                 = each.value.spot_allocation_strategy
    }

    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.unreal_horde_agent_template[each.key].id
        version            = "$Latest"
      }

      dynamic "override" {
        for_each = each.value.instance_types
        content {
          instance_type = override.value
        }
      }
    }
  }

  tag {
    key                 = "Horde_Autoscale_Pool"
    value               = each.value.horde_pool_name == null ? each.key : each.value.horde_pool_name
    propagate_at_launch = false
  }

  tag {
    key                 = "Horde_Autoscale_PoolId"
    value               = each.value.horde_pool_name == null ? each.key : each.value.horde_pool_name
    propagate_at_launch = false
  }

  tag {
    key                 = "Name"
    value               = "${each.key} Horde Agent ASG"
    propagate_at_launch = false
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 0
      instance_warmup        = 60
    }
  }

  depends_on = [aws_instance.horde_host]
}

data "aws_iam_policy_document" "ec2_trust_relationship" {
  count = length(var.agents) > 0 ? 1 : 0
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "horde_agents_s3_policy" {
  count = length(var.agents) > 0 ? 1 : 0
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutObject",
      "s3:PutObjectAcl",
      "s3:GetEncryptionConfiguration"
    ]
    resources = [
      aws_s3_bucket.ansible_playbooks[0].arn,
      "${aws_s3_bucket.ansible_playbooks[0].arn}/*"
    ]
  }
}

data "aws_iam_policy_document" "horde_agents_ec2_policy" {
  count = length(var.agents) > 0 ? 1 : 0
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeTags",
    ]
    resources = [
      "*"
    ]
  }
}

resource "aws_iam_policy" "horde_agents_s3_policy" {
  count       = length(var.agents) > 0 ? 1 : 0
  name        = "${var.project_prefix}-horde-agents-s3-policy"
  description = "Policy granting Horde Agent EC2 instances access to Amazon S3."
  policy      = data.aws_iam_policy_document.horde_agents_s3_policy[0].json
}

resource "aws_iam_policy" "horde_agents_ec2_policy" {
  count       = length(var.agents) > 0 ? 1 : 0
  name        = "${var.project_prefix}-horde-agents-ec2-policy"
  description = "Policy granting Horde Agent EC2 instances access to Amazon EC2 APIs."
  policy      = data.aws_iam_policy_document.horde_agents_ec2_policy[0].json
}

resource "aws_iam_role" "unreal_horde_agent_default_role" {
  count              = length(var.agents) > 0 ? 1 : 0
  name               = "${var.project_prefix}-horde-agent-instance-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust_relationship[0].json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "unreal_horde_agent_policy_attachments" {
  count      = length(var.agents) > 0 ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.unreal_horde_agent_default_role[0].name
}

resource "aws_iam_role_policy_attachment" "unreal_horde_agents_s3_policy" {
  count      = length(var.agents) > 0 ? 1 : 0
  policy_arn = aws_iam_policy.horde_agents_s3_policy[0].arn
  role       = aws_iam_role.unreal_horde_agent_default_role[0].name
}

resource "aws_iam_role_policy_attachment" "unreal_horde_agents_ec2_policy" {
  count      = length(var.agents) > 0 ? 1 : 0
  policy_arn = aws_iam_policy.horde_agents_ec2_policy[0].arn
  role       = aws_iam_role.unreal_horde_agent_default_role[0].name
}

resource "aws_iam_instance_profile" "unreal_horde_agent_instance_profile" {
  count = length(var.agents) > 0 ? 1 : 0
  name  = "${var.project_prefix}-horde-agent-instance-profile"
  role  = aws_iam_role.unreal_horde_agent_default_role[0].name
}

resource "random_string" "unreal_horde_ansible_playbooks_bucket_suffix" {
  count   = length(var.agents) > 0 ? 1 : 0
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket" "ansible_playbooks" {
  count  = length(var.agents) > 0 ? 1 : 0
  bucket = "${var.project_prefix}-horde-ansible-playbooks-${random_string.unreal_horde_ansible_playbooks_bucket_suffix[0].id}"

  #checkov:skip=CKV_AWS_144: Cross-region replication not necessary
  #checkov:skip=CKV_AWS_145: KMS encryption with CMK not currently supported
  #checkov:skip=CKV_AWS_18: S3 access logs not necessary
  #checkov:skip=CKV2_AWS_62: Event notifications not necessary
  #checkov:skip=CKV2_AWS_61: Lifecycle configuration not necessary
  #checkov:skip=CKV2_AWS_6: Public access block conditionally defined
  #checkov:skip=CKV_AWS_21: Versioning enabled conditionally

  tags                = local.tags
  object_lock_enabled = true
  force_destroy       = true
}

resource "aws_s3_bucket_versioning" "ansible_playbooks_versioning" {
  count  = length(var.agents) > 0 ? 1 : 0
  bucket = aws_s3_bucket.ansible_playbooks[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "ansible_playbooks_bucket_public_block" {
  count = length(var.agents) > 0 ? 1 : 0

  depends_on              = [aws_s3_bucket.ansible_playbooks[0]]
  bucket                  = aws_s3_bucket.ansible_playbooks[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "unreal_horde_agent_playbook" {
  count         = length(var.agents) > 0 ? 1 : 0
  bucket        = aws_s3_bucket.ansible_playbooks[0].id
  key           = "/agent/horde-agent.ansible.yml"
  source        = "${path.module}/config/agent/horde-agent.ansible.yml"
  etag          = filemd5("${path.module}/config/agent/horde-agent.ansible.yml")
  force_destroy = true
}

resource "aws_s3_object" "unreal_horde_agent_service" {
  count         = length(var.agents) > 0 ? 1 : 0
  bucket        = aws_s3_bucket.ansible_playbooks[0].id
  key           = "/agent/horde-agent.service"
  source        = "${path.module}/config/agent/horde-agent.service"
  etag          = filemd5("${path.module}/config/agent/horde-agent.service")
  force_destroy = true
}

locals {
  # Launch-template IDs for Linux agent pools only. The Ansible-based agent
  # bootstrap is Linux-specific; Windows agents are configured via their AMI's
  # baked-in user data.
  linux_agent_launch_template_ids = [
    for name, lt in aws_launch_template.unreal_horde_agent_template :
    lt.id if data.aws_ami.unreal_horde_agent_ami[name].platform == ""
  ]
}

resource "aws_ssm_document" "ansible_run_document" {
  count         = length(local.linux_agent_launch_template_ids) > 0 ? 1 : 0
  document_type = "Command"
  name          = "${var.project_prefix}-AnsibleRun"
  content       = file("${path.module}/config/ssm/AnsibleRunCommand.json")
  tags          = local.tags
}

resource "aws_ssm_association" "configure_unreal_horde_agent" {
  count            = length(local.linux_agent_launch_template_ids) > 0 ? 1 : 0
  association_name = "${var.project_prefix}-ConfigureHordeAgent"
  name             = aws_ssm_document.ansible_run_document[0].name
  parameters = {
    SourceInfo     = "{\"path\":\"https://${aws_s3_bucket.ansible_playbooks[0].bucket_domain_name}/agent/\"}"
    PlaybookFile   = "horde-agent.ansible.yml"
    ExtraVariables = "horde_server_url=${var.fully_qualified_domain_name} dotnet_runtime_version=${var.agent_dotnet_runtime_version}"
  }

  output_location {
    s3_bucket_name = aws_s3_bucket.ansible_playbooks[0].bucket
    s3_key_prefix  = "logs"
  }

  targets {
    key    = "tag:aws:ec2launchtemplate:id"
    values = local.linux_agent_launch_template_ids
  }

  depends_on = [aws_instance.horde_host]
}
