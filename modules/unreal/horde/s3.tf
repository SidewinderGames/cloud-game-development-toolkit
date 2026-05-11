resource "random_string" "horde_storage_suffix" {
  count   = var.create_s3_storage_bucket ? 1 : 0
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket" "horde_storage" {
  #checkov:skip=CKV_AWS_144: Cross-region replication unnecessary for studio-scale artifact storage
  #checkov:skip=CKV_AWS_145: KMS CMK encryption deferred; SSE-S3 is sufficient at this scale
  #checkov:skip=CKV_AWS_18:  S3 access logs deferred
  #checkov:skip=CKV2_AWS_62: Event notifications not required
  count  = var.create_s3_storage_bucket ? 1 : 0
  bucket = "${local.name_prefix}-storage-${random_string.horde_storage_suffix[0].result}"

  force_destroy = var.s3_force_destroy
  tags          = local.tags
}

resource "aws_s3_bucket_versioning" "horde_storage" {
  count  = var.create_s3_storage_bucket ? 1 : 0
  bucket = aws_s3_bucket.horde_storage[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "horde_storage" {
  count  = var.create_s3_storage_bucket ? 1 : 0
  bucket = aws_s3_bucket.horde_storage[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "horde_storage" {
  count                   = var.create_s3_storage_bucket ? 1 : 0
  bucket                  = aws_s3_bucket.horde_storage[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "horde_storage" {
  count  = var.create_s3_storage_bucket ? 1 : 0
  bucket = aws_s3_bucket.horde_storage[0].id

  rule {
    id     = "artifacts-cold-tier"
    status = "Enabled"

    filter {
      prefix = "horde/artifacts/"
    }

    transition {
      days          = var.s3_artifact_transition_ia_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.s3_artifact_transition_glacier_days
      storage_class = "GLACIER_IR"
    }

    expiration {
      days = var.s3_artifact_expiration_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  rule {
    id     = "logs-expire"
    status = "Enabled"

    filter {
      prefix = "horde/logs/"
    }

    expiration {
      days = var.s3_log_expiration_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

data "aws_iam_policy_document" "horde_storage_access" {
  count = var.create_s3_storage_bucket ? 1 : 0

  statement {
    sid    = "AllowHordeHostRole"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.unreal_horde_default_role[0].arn]
    }

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
      "s3:GetBucketLocation",
    ]

    resources = [
      aws_s3_bucket.horde_storage[0].arn,
      "${aws_s3_bucket.horde_storage[0].arn}/*",
    ]
  }

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.horde_storage[0].arn,
      "${aws_s3_bucket.horde_storage[0].arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "horde_storage" {
  count  = var.create_s3_storage_bucket ? 1 : 0
  bucket = aws_s3_bucket.horde_storage[0].id
  policy = data.aws_iam_policy_document.horde_storage_access[0].json
}
