data "aws_iam_policy_document" "ec2_host_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "unreal_horde_default_policy" {
  count = var.create_unreal_horde_default_policy ? 1 : 0
  statement {
    sid    = "SSMExec"
    effect = "Allow"
    actions = [
      "ssmmessages:OpenDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:CreateControlChannel",
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "unreal_horde_recycle_policy" {
  count = var.create_unreal_horde_recycle_policy ? 1 : 0
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:DescribeSpotPriceHistory",
      "ec2:RunInstances",
      "ec2:StartInstances",
      "ec2:StopInstances",
      "ec2:TerminateInstances",
      "ec2:ModifyInstanceAttribute",
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:SetDesiredCapacity",
      "autoscaling:UpdateAutoScalingGroup",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "autoscaling:CompleteLifecycleAction",
      "autoscaling:RecordLifecycleActionHeartbeat",
    ]
    resources = ["*"]
  }

  # EBS data volume orchestration for the AwsAsgWithDataVolumes fleet
  # strategy. The Horde server creates, attaches, detaches, snapshots,
  # rotates, and tags per-pool EBS volumes via these APIs. Snapshot perms
  # are required by the snapshot-on-detach rotation flow (cost-saving:
  # converts always-billed gp3 storage into changed-block snapshot
  # storage between runs). DescribeVolumes / DescribeSnapshots are
  # read-only and must be wildcard; the mutating operations could be
  # tightened with an aws:ResourceTag/Horde:DataVolumePool condition.
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeVolumes",
      "ec2:CreateVolume",
      "ec2:DeleteVolume",
      "ec2:AttachVolume",
      "ec2:DetachVolume",
      "ec2:DescribeSnapshots",
      "ec2:CreateSnapshot",
      "ec2:DeleteSnapshot",
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "unreal_horde_asg_lifecycle_sqs" {
  count = length(var.agents) > 0 ? 1 : 0
  statement {
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
    ]
    resources = [aws_sqs_queue.asg_lifecycle[0].arn]
  }
}

resource "aws_iam_policy" "unreal_horde_asg_lifecycle_sqs" {
  count       = length(var.agents) > 0 ? 1 : 0
  name        = "${var.project_prefix}-unreal_horde-asg-lifecycle-sqs"
  description = "Allow Horde server to consume ASG lifecycle events from the per-deployment SQS queue."
  policy      = data.aws_iam_policy_document.unreal_horde_asg_lifecycle_sqs[0].json
}

resource "aws_iam_role_policy_attachment" "unreal_horde_asg_lifecycle_sqs" {
  count      = length(var.agents) > 0 && var.create_unreal_horde_default_role ? 1 : 0
  role       = aws_iam_role.unreal_horde_default_role[0].name
  policy_arn = aws_iam_policy.unreal_horde_asg_lifecycle_sqs[0].arn
}

data "aws_iam_policy_document" "unreal_horde_storage_policy" {
  count = var.create_s3_storage_bucket ? 1 : 0
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]
    resources = ["${aws_s3_bucket.horde_storage[0].arn}/*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
      "s3:GetBucketLocation",
    ]
    resources = [aws_s3_bucket.horde_storage[0].arn]
  }
}

data "aws_iam_policy_document" "unreal_horde_secrets_manager_policy" {
  count = var.github_credentials_secret_arn != null || var.p4_super_user_username_secret_arn != null ? 1 : 0
  statement {
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    resources = concat(
      [aws_secretsmanager_secret.mongo.arn],
      var.github_credentials_secret_arn != null ? [var.github_credentials_secret_arn] : [],
      var.p4_super_user_username_secret_arn != null ? [
        var.p4_super_user_username_secret_arn,
        var.p4_super_user_password_secret_arn,
      ] : [],
    )
  }
}

resource "aws_iam_policy" "unreal_horde_default_policy" {
  count       = var.create_unreal_horde_default_policy ? 1 : 0
  name        = "${var.project_prefix}-unreal_horde-default-policy"
  description = "Default permissions for the Horde server EC2 host (SSM)."
  policy      = data.aws_iam_policy_document.unreal_horde_default_policy[0].json
}

resource "aws_iam_policy" "unreal_horde_recycle_policy" {
  count       = var.create_unreal_horde_recycle_policy ? 1 : 0
  name        = "${var.project_prefix}-unreal_horde-recycle-policy"
  description = "Permissions for Horde server to drive ASG scaling via the AwsAsg fleet manager."
  policy      = data.aws_iam_policy_document.unreal_horde_recycle_policy[0].json
}

resource "aws_iam_policy" "unreal_horde_storage_policy" {
  count       = var.create_s3_storage_bucket ? 1 : 0
  name        = "${var.project_prefix}-unreal_horde-storage-policy"
  description = "Permissions for Horde to read and write artifacts and logs to the storage bucket."
  policy      = data.aws_iam_policy_document.unreal_horde_storage_policy[0].json
}

resource "aws_iam_policy" "unreal_horde_secrets_manager_policy" {
  count       = var.github_credentials_secret_arn != null || var.p4_super_user_username_secret_arn != null ? 1 : 0
  name        = "${var.project_prefix}-unreal-horde-secrets-manager-policy"
  description = "Permissions for the Horde host to read GHCR creds, Mongo password, and P4 super-user creds from Secrets Manager."
  policy      = data.aws_iam_policy_document.unreal_horde_secrets_manager_policy[0].json
}

resource "aws_iam_role" "unreal_horde_default_role" {
  count              = var.create_unreal_horde_default_role ? 1 : 0
  name               = "${var.project_prefix}-unreal_horde-host-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_host_trust.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "ssm_managed" {
  count      = var.create_unreal_horde_default_role ? 1 : 0
  role       = aws_iam_role.unreal_horde_default_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "unreal_horde_default_policy_attachment" {
  count      = var.create_unreal_horde_default_policy ? 1 : 0
  role       = aws_iam_role.unreal_horde_default_role[0].name
  policy_arn = aws_iam_policy.unreal_horde_default_policy[0].arn
}

resource "aws_iam_role_policy_attachment" "unreal_horde_recycle_attachment" {
  count      = var.create_unreal_horde_recycle_policy ? 1 : 0
  role       = aws_iam_role.unreal_horde_default_role[0].name
  policy_arn = aws_iam_policy.unreal_horde_recycle_policy[0].arn
}

resource "aws_iam_role_policy_attachment" "unreal_horde_storage_attachment" {
  count      = var.create_s3_storage_bucket ? 1 : 0
  role       = aws_iam_role.unreal_horde_default_role[0].name
  policy_arn = aws_iam_policy.unreal_horde_storage_policy[0].arn
}

resource "aws_iam_role_policy_attachment" "unreal_horde_secrets_manager_policy_attachment" {
  count      = (var.github_credentials_secret_arn != null || var.p4_super_user_username_secret_arn != null) ? 1 : 0
  role       = aws_iam_role.unreal_horde_default_role[0].name
  policy_arn = aws_iam_policy.unreal_horde_secrets_manager_policy[0].arn
}

resource "aws_iam_role_policy_attachment" "unreal_horde_ecr_attachment" {
  count      = var.enable_ecr_pull ? 1 : 0
  role       = aws_iam_role.unreal_horde_default_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "horde_host" {
  name = "${var.project_prefix}-unreal_horde-host-profile"
  role = aws_iam_role.unreal_horde_default_role[0].name
}
