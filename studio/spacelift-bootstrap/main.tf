locals {
  # Spacelift-owned AWS account IDs trusted in the role's assume-role policy.
  # https://docs.spacelift.io/integrations/cloud-providers/aws documents these.
  spacelift_principal_account_id_by_region = {
    ""   = "324880187172" # accounts on app.spacelift.io
    "us" = "577638371743" # accounts on app.us.spacelift.io
  }

  spacelift_principal_account_id = coalesce(
    var.spacelift_aws_principal_account_id_override,
    local.spacelift_principal_account_id_by_region[var.spacelift_account_region],
  )

  # External IDs Spacelift mints have the form:
  #   <account-name>@<integration-id>@<stack-slug>@<read|write>
  # Allowing <account-name>@* permits the integration's validation call plus
  # any stack this integration is attached to. Tighten per-stack later by
  # listing explicit external-id prefixes here.
  external_id_patterns = ["${var.spacelift_account_name}@*"]
}

data "aws_iam_policy_document" "spacelift_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.spacelift_principal_account_id}:root"]
    }

    condition {
      test     = "StringLike"
      variable = "sts:ExternalId"
      values   = local.external_id_patterns
    }
  }
}

resource "aws_iam_role" "spacelift_runner" {
  name                 = var.iam_role_name
  description          = "Role Spacelift's native AWS Cloud Integration assumes via sts:AssumeRole with the external-id prefix '${var.spacelift_account_name}@'."
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
