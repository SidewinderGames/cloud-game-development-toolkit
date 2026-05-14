###########################
# External Load Balancer
###########################
resource "aws_lb" "unreal_horde_external_alb" {
  count              = var.create_external_alb ? 1 : 0
  name               = "${local.name_prefix}-ext-alb"
  load_balancer_type = "application"
  subnets            = var.unreal_horde_external_alb_subnets
  security_groups    = concat(var.existing_security_groups, [aws_security_group.unreal_horde_external_alb_sg[0].id])

  dynamic "access_logs" {
    for_each = var.enable_unreal_horde_alb_access_logs ? [1] : []
    content {
      enabled = var.enable_unreal_horde_alb_access_logs
      bucket  = var.unreal_horde_alb_access_logs_bucket != null ? var.unreal_horde_alb_access_logs_bucket : aws_s3_bucket.unreal_horde_alb_access_logs_bucket[0].id
      prefix  = var.unreal_horde_alb_access_logs_prefix != null ? var.unreal_horde_alb_access_logs_prefix : "${local.name_prefix}-alb"
    }
  }

  #checkov:skip=CKV_AWS_150: Deletion protection disabled by default
  #checkov:skip=CKV2_AWS_28: ALB access is managed with SG allow-listing
  enable_deletion_protection = var.enable_unreal_horde_alb_deletion_protection

  drop_invalid_header_fields = true

  tags = local.tags
}

resource "aws_lb_target_group" "unreal_horde_api_target_group_external" {
  #checkov:skip=CKV_AWS_378: Using ALB for TLS termination
  count       = var.create_external_alb ? 1 : 0
  name        = "${local.name_prefix}-ext-api-tg"
  port        = var.container_api_port
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = var.vpc_id

  health_check {
    path                = "/health/ok"
    protocol            = "HTTP"
    matcher             = "200"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 10
    interval            = 30
  }

  tags = local.tags
}

resource "aws_lb_target_group" "unreal_horde_grpc_target_group_external" {
  #checkov:skip=CKV_AWS_378: Using ALB for TLS termination
  #checkov:skip=CKV_AWS_261: No health check defined for gRPC target group
  count            = var.create_external_alb ? 1 : 0
  name             = "${local.name_prefix}-ext-grpc-tg"
  port             = var.container_grpc_port
  protocol         = "HTTP"
  protocol_version = "HTTP2"
  target_type      = "instance"
  vpc_id           = var.vpc_id

  tags = local.tags
}

resource "aws_lb_target_group_attachment" "unreal_horde_api_external" {
  count            = var.create_external_alb ? 1 : 0
  target_group_arn = aws_lb_target_group.unreal_horde_api_target_group_external[0].arn
  target_id        = aws_instance.horde_host.id
  port             = var.container_api_port
}

resource "aws_lb_target_group_attachment" "unreal_horde_grpc_external" {
  count            = var.create_external_alb ? 1 : 0
  target_group_arn = aws_lb_target_group.unreal_horde_grpc_target_group_external[0].arn
  target_id        = aws_instance.horde_host.id
  port             = var.container_grpc_port
}

resource "aws_lb_listener" "unreal_horde_external_alb_https_listener" {
  count             = var.create_external_alb ? 1 : 0
  load_balancer_arn = aws_lb.unreal_horde_external_alb[0].arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    target_group_arn = aws_lb_target_group.unreal_horde_api_target_group_external[0].arn
    type             = "forward"
  }

  tags = local.tags
}

# Horde Agents connect to https://<fqdn>:443 for both REST and gRPC. The
# default 443 listener forwards to the HTTP/1 API target group, which fails
# gRPC requests with HTTP 464 (incompatible protocols). Add a rule that
# matches Content-Type: application/grpc* and forwards to the HTTP/2 gRPC
# target group so the agent doesn't need to know about port 8080.
resource "aws_lb_listener_rule" "unreal_horde_external_alb_grpc_on_443" {
  count        = var.create_external_alb ? 1 : 0
  listener_arn = aws_lb_listener.unreal_horde_external_alb_https_listener[0].arn
  priority     = 1

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.unreal_horde_grpc_target_group_external[0].arn
  }

  condition {
    http_header {
      http_header_name = "Content-Type"
      values = [
        "application/grpc",
        "application/grpc+proto",
        "application/grpc+json",
        "application/grpc*",
      ]
    }
  }

  tags = local.tags
}

resource "aws_lb_listener" "unreal_horde_external_alb_http_listener" {
  count             = var.create_external_alb ? 1 : 0
  load_balancer_arn = aws_lb.unreal_horde_external_alb[0].arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      status_code = "HTTP_301"
      protocol    = "HTTPS"
      port        = aws_lb_listener.unreal_horde_external_alb_https_listener[0].port
    }
  }

  tags = local.tags
}

# Dedicated gRPC listener on the gRPC port (default 8080). Horde agents
# connect here for HTTP/2 RPC streams. ALB terminates TLS and forwards to the
# Horde host's container_grpc_port.
resource "aws_lb_listener" "unreal_horde_external_alb_grpc_listener" {
  count             = var.create_external_alb ? 1 : 0
  load_balancer_arn = aws_lb.unreal_horde_external_alb[0].arn
  port              = var.container_grpc_port
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    target_group_arn = aws_lb_target_group.unreal_horde_grpc_target_group_external[0].arn
    type             = "forward"
  }

  tags = local.tags
}

###########################
# Access Logs (gated)
###########################

resource "random_string" "unreal_horde_alb_access_logs_bucket_suffix" {
  count   = var.enable_unreal_horde_alb_access_logs && var.unreal_horde_alb_access_logs_bucket == null ? 1 : 0
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket" "unreal_horde_alb_access_logs_bucket" {
  #checkov:skip=CKV_AWS_21: Versioning unnecessary for access logs
  #checkov:skip=CKV_AWS_144: Cross-region replication unnecessary for access logs
  #checkov:skip=CKV_AWS_145: KMS CMK encryption not currently supported
  #checkov:skip=CKV_AWS_18:  S3 access logs unnecessary on access-log bucket itself
  #checkov:skip=CKV2_AWS_62: Event notifications unnecessary
  count         = var.enable_unreal_horde_alb_access_logs && var.unreal_horde_alb_access_logs_bucket == null ? 1 : 0
  bucket        = "${local.name_prefix}-alb-access-logs-${random_string.unreal_horde_alb_access_logs_bucket_suffix[0].result}"
  force_destroy = true

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-alb-access-logs"
  })
}

data "aws_elb_service_account" "main" {}

data "aws_iam_policy_document" "access_logs_bucket_alb_write" {
  count = var.enable_unreal_horde_alb_access_logs && var.unreal_horde_alb_access_logs_bucket == null ? 1 : 0
  statement {
    effect  = "Allow"
    actions = ["s3:PutObject"]
    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.main.arn]
    }
    resources = ["${aws_s3_bucket.unreal_horde_alb_access_logs_bucket[0].arn}/${var.unreal_horde_alb_access_logs_prefix != null ? var.unreal_horde_alb_access_logs_prefix : "${local.name_prefix}-alb"}/*"]
  }
}

resource "aws_s3_bucket_policy" "alb_access_logs_bucket_policy" {
  count  = var.enable_unreal_horde_alb_access_logs && var.unreal_horde_alb_access_logs_bucket == null ? 1 : 0
  bucket = aws_s3_bucket.unreal_horde_alb_access_logs_bucket[0].id
  policy = data.aws_iam_policy_document.access_logs_bucket_alb_write[0].json
}

resource "aws_s3_bucket_lifecycle_configuration" "access_logs_bucket_lifecycle_configuration" {
  count  = var.enable_unreal_horde_alb_access_logs && var.unreal_horde_alb_access_logs_bucket == null ? 1 : 0
  bucket = aws_s3_bucket.unreal_horde_alb_access_logs_bucket[0].id

  rule {
    id     = "access-logs-lifecycle"
    status = "Enabled"
    filter {}
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    expiration {
      days = 90
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_public_access_block" "access_logs_bucket_public_block" {
  count                   = var.enable_unreal_horde_alb_access_logs && var.unreal_horde_alb_access_logs_bucket == null ? 1 : 0
  bucket                  = aws_s3_bucket.unreal_horde_alb_access_logs_bucket[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
