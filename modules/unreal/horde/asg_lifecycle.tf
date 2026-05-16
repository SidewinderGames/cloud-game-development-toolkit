########################################
# ASG LIFECYCLE HOOKS + SQS for AwsAsgWithDataVolumes fleet strategy.
#
# Each agent pool ASG has two lifecycle hooks:
#   - EC2_INSTANCE_LAUNCHING: pauses fresh instances in Pending:Wait so the Horde
#     server can attach (or create) the per-pool EBS data volume before the agent
#     boots. Without this the ASG cannot scale from zero with a warm workspace.
#   - EC2_INSTANCE_TERMINATING: existing graceful-shutdown path. Allows the
#     Horde server to drain the agent and detach the volume cleanly before AWS
#     reclaims the instance.
#
# Both hooks publish to a single SQS queue per deployment; the Horde server
# polls it via AwsAutoScalingLifecycleService.
#
# See Engine/Source/Programs/Horde/Docs/Internals/AwsAsgWithDataVolumes.md.
########################################

resource "aws_sqs_queue" "asg_lifecycle" {
  count                     = length(var.agents) > 0 ? 1 : 0
  name                      = "${local.name_prefix}-asg-lifecycle"
  message_retention_seconds = 1209600 # 14 days
  visibility_timeout_seconds = 60
  sqs_managed_sse_enabled   = true
  tags                      = local.tags
}

# IAM role assumed by ASG to publish lifecycle messages to the queue.
data "aws_iam_policy_document" "asg_lifecycle_trust" {
  count = length(var.agents) > 0 ? 1 : 0
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["autoscaling.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "asg_lifecycle_publish" {
  count = length(var.agents) > 0 ? 1 : 0
  statement {
    effect    = "Allow"
    actions   = ["sqs:SendMessage", "sqs:GetQueueUrl"]
    resources = [aws_sqs_queue.asg_lifecycle[0].arn]
  }
}

resource "aws_iam_role" "asg_lifecycle" {
  count              = length(var.agents) > 0 ? 1 : 0
  name               = "${local.name_prefix}-asg-lifecycle-role"
  assume_role_policy = data.aws_iam_policy_document.asg_lifecycle_trust[0].json
  tags               = local.tags
}

resource "aws_iam_role_policy" "asg_lifecycle" {
  count  = length(var.agents) > 0 ? 1 : 0
  name   = "publish-to-asg-lifecycle-queue"
  role   = aws_iam_role.asg_lifecycle[0].id
  policy = data.aws_iam_policy_document.asg_lifecycle_publish[0].json
}

# Launching hook: pauses each new instance in Pending:Wait until the Horde
# server attaches a data volume and signals CompleteLifecycleAction. Defaults
# to ABANDON if the heartbeat times out - the ASG terminates the instance and
# retries on the next desired-capacity change, which is the safe failure mode
# (no orphaned instance booting without its workspace).
resource "aws_autoscaling_lifecycle_hook" "launching" {
  for_each = {
    for k, v in var.agents : k => v
    if v.create_asg && try(v.data_volume, null) != null
  }

  name                    = "${local.name_prefix}-${each.key}-launching"
  autoscaling_group_name  = aws_autoscaling_group.unreal_horde_agent_asg[each.key].name
  lifecycle_transition    = "autoscaling:EC2_INSTANCE_LAUNCHING"
  heartbeat_timeout       = 600
  default_result          = "ABANDON"
  notification_target_arn = aws_sqs_queue.asg_lifecycle[0].arn
  role_arn                = aws_iam_role.asg_lifecycle[0].arn
}

# Terminating hook: existing graceful-shutdown path. Default CONTINUE so a
# server-side outage doesn't strand an instance the user is trying to scale
# in - AWS reclaims it after the timeout.
resource "aws_autoscaling_lifecycle_hook" "terminating" {
  for_each = {
    for k, v in var.agents : k => v
    if v.create_asg && try(v.data_volume, null) != null
  }

  name                    = "${local.name_prefix}-${each.key}-terminating"
  autoscaling_group_name  = aws_autoscaling_group.unreal_horde_agent_asg[each.key].name
  lifecycle_transition    = "autoscaling:EC2_INSTANCE_TERMINATING"
  heartbeat_timeout       = 600
  default_result          = "CONTINUE"
  notification_target_arn = aws_sqs_queue.asg_lifecycle[0].arn
  role_arn                = aws_iam_role.asg_lifecycle[0].arn
}
