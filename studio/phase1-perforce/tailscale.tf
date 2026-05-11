###############################################################################
# Tailscale subnet router
#
# Advertises the studio VPC CIDR to the Sidewinder tailnet so team members
# can reach private AWS endpoints (P4 server, eventually Horde) without
# managing an IP whitelist.
#
# Prerequisites before the first terraform apply:
#   1. Generate a Tailscale auth key in the tailnet admin (Settings -> Keys):
#        Reusable:        no
#        Ephemeral:       no
#        Pre-authorized:  yes
#        Tags:            tag:subnet-router (define in the ACL first)
#        Expiration:      90 days (longest supported on most plans)
#   2. Store it in AWS Secrets Manager under the name configured via
#      var.tailscale_auth_key_secret_name (default sidewinder/tailscale-auth-key):
#        aws secretsmanager create-secret \
#          --region us-east-1 \
#          --name sidewinder/tailscale-auth-key \
#          --secret-string "tskey-auth-..."
#   3. In the Tailscale ACL, define tag:subnet-router with autoApprovers for
#      the VPC CIDR. Example ACL in studio/TAILSCALE.md.
#
# After the relay is up, verify in https://login.tailscale.com/admin/machines
# that the node sidewinder-aws-relay appears with the route 10.40.0.0/16
# already approved (autoApprovers handles this).
###############################################################################

data "aws_ami" "al2023_arm64" {
  count       = var.create_tailscale_relay ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-arm64"]
  }
  filter {
    name   = "architecture"
    values = ["arm64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_secretsmanager_secret" "tailscale_auth_key" {
  count = var.create_tailscale_relay ? 1 : 0
  name  = var.tailscale_auth_key_secret_name
}

resource "aws_security_group" "tailscale_relay" {
  count       = var.create_tailscale_relay ? 1 : 0
  name        = "${local.project_prefix}-tailscale-relay"
  description = "Tailscale subnet router. Outbound only - inbound is via WireGuard."
  vpc_id      = aws_vpc.studio.id

  tags = {
    Name = "${local.project_prefix}-tailscale-relay"
  }
}

resource "aws_vpc_security_group_egress_rule" "tailscale_relay_all_out" {
  count             = var.create_tailscale_relay ? 1 : 0
  security_group_id = aws_security_group.tailscale_relay[0].id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Tailscale needs UDP 41641 + HTTPS to coordination servers; allowing all egress is simplest."
}

data "aws_iam_policy_document" "tailscale_relay_trust" {
  count = var.create_tailscale_relay ? 1 : 0
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "tailscale_relay" {
  count              = var.create_tailscale_relay ? 1 : 0
  name               = "${local.project_prefix}-tailscale-relay"
  assume_role_policy = data.aws_iam_policy_document.tailscale_relay_trust[0].json

  tags = {
    Name = "${local.project_prefix}-tailscale-relay"
  }
}

resource "aws_iam_role_policy_attachment" "tailscale_relay_ssm" {
  count      = var.create_tailscale_relay ? 1 : 0
  role       = aws_iam_role.tailscale_relay[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "tailscale_relay_secret_read" {
  count = var.create_tailscale_relay ? 1 : 0
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [data.aws_secretsmanager_secret.tailscale_auth_key[0].arn]
  }
}

resource "aws_iam_role_policy" "tailscale_relay_secret_read" {
  count  = var.create_tailscale_relay ? 1 : 0
  name   = "tailscale-auth-key-read"
  role   = aws_iam_role.tailscale_relay[0].id
  policy = data.aws_iam_policy_document.tailscale_relay_secret_read[0].json
}

resource "aws_iam_instance_profile" "tailscale_relay" {
  count = var.create_tailscale_relay ? 1 : 0
  name  = "${local.project_prefix}-tailscale-relay"
  role  = aws_iam_role.tailscale_relay[0].name
}

resource "aws_instance" "tailscale_relay" {
  count = var.create_tailscale_relay ? 1 : 0

  ami                         = data.aws_ami.al2023_arm64[0].id
  instance_type               = var.tailscale_relay_instance_type
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.tailscale_relay[0].id]
  iam_instance_profile        = aws_iam_instance_profile.tailscale_relay[0].name
  associate_public_ip_address = true
  ebs_optimized               = true
  monitoring                  = false

  source_dest_check = false # required so the kernel can route packets between subnets and Tailscale

  root_block_device {
    encrypted             = true
    volume_size           = 8
    volume_type           = "gp3"
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }

  user_data = base64encode(templatefile("${path.module}/tailscale_user_data.sh.tftpl", {
    region           = var.aws_region
    secret_name      = var.tailscale_auth_key_secret_name
    hostname         = var.tailscale_relay_hostname
    advertise_routes = var.tailscale_advertise_routes
    advertise_tags   = var.tailscale_relay_tags
    enable_ssh       = var.tailscale_relay_enable_ssh
  }))

  user_data_replace_on_change = true

  tags = {
    Name = "${local.project_prefix}-tailscale-relay"
  }

  lifecycle {
    ignore_changes = [ami]
  }
}

# Add a parallel ingress on the P4 user-access SG so anything coming from the
# Tailscale relay can reach the P4 server on 1666. This is ADDITIVE to the
# IP whitelist; the whitelist keeps working in parallel until cutover. To
# disable the whitelist later, empty out var.allowed_p4_cidrs.
resource "aws_vpc_security_group_ingress_rule" "p4_from_tailscale" {
  count                        = var.create_tailscale_relay ? 1 : 0
  security_group_id            = aws_security_group.p4_user_access.id
  referenced_security_group_id = aws_security_group.tailscale_relay[0].id
  ip_protocol                  = "tcp"
  from_port                    = 1666
  to_port                      = 1666
  description                  = "P4 ingress via Tailscale subnet router."
}
