locals {
  spacelift_issuer_url = "https://${var.spacelift_account_name}.app.spacelift.io"
  spacelift_audience   = "${var.spacelift_account_name}.app.spacelift.io"

  # Permit any subject within the configured Spacelift space. This is what
  # Spacelift's own docs recommend (space:<space_id>:*) and what the AWS
  # integration's pre-flight validation requires - that test call doesn't
  # carry a stack-specific subject. The trust is still narrowed by:
  #   - the OIDC issuer (only Spacelift's account)
  #   - the aud claim (the account name)
  #   - the space (anything outside `root` is rejected)
  # To tighten further once everything is stable, swap this for a list of
  # per-stack patterns like:
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
