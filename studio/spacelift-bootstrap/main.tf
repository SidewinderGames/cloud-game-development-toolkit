locals {
  spacelift_region_segment = var.spacelift_account_region == "" ? "" : ".${var.spacelift_account_region}"
  spacelift_hostname       = "${var.spacelift_account_name}.app${local.spacelift_region_segment}.spacelift.io"
  spacelift_issuer_url     = "https://${local.spacelift_hostname}"
  spacelift_audience       = local.spacelift_hostname

  # Allow any subject from the configured Spacelift space. Spacelift's own
  # docs example uses this pattern: space:<space_id>:*. The trust is narrowed by
  # the OIDC issuer (only this Spacelift account) and the aud claim. To tighten
  # to per-stack subjects later, swap this for a list like:
  #   "space:root:stack:sidewinder-phase1-perforce:run_type:*:scope:*"
  oidc_sub_patterns = ["space:${var.spacelift_space_id}:*"]
}

data "tls_certificate" "spacelift" {
  url = local.spacelift_issuer_url
}

resource "aws_iam_openid_connect_provider" "spacelift" {
  url             = local.spacelift_issuer_url
  client_id_list  = [local.spacelift_audience]
  thumbprint_list = [data.tls_certificate.spacelift.certificates[0].sha1_fingerprint]

  tags = {
    Name = "spacelift-${var.spacelift_account_name}"
  }
}

data "aws_iam_policy_document" "spacelift_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.spacelift.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.spacelift.url, "https://", "")}:aud"
      values   = [local.spacelift_audience]
    }

    condition {
      test     = "StringLike"
      variable = "${replace(aws_iam_openid_connect_provider.spacelift.url, "https://", "")}:sub"
      values   = local.oidc_sub_patterns
    }
  }
}

resource "aws_iam_role" "spacelift_runner" {
  name                 = var.iam_role_name
  description          = "Role Spacelift assumes from its runners via OIDC to deploy Sidewinder infrastructure."
  assume_role_policy   = data.aws_iam_policy_document.spacelift_trust.json
  max_session_duration = 3600

  tags = {
    Name = var.iam_role_name
  }
}

resource "aws_iam_role_policy_attachment" "admin" {
  role       = aws_iam_role.spacelift_runner.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
