output "spacelift_runner_role_arn" {
  description = "ARN of the IAM role Spacelift's native AWS Cloud Integration assumes. Paste into the Spacelift integration's Role ARN field."
  value       = aws_iam_role.spacelift_runner.arn
}

output "spacelift_runner_role_name" {
  description = "Name of the IAM role."
  value       = aws_iam_role.spacelift_runner.name
}

output "spacelift_principal_account_id" {
  description = "Spacelift-owned AWS account ID trusted by this role. Differs by region (us vs default)."
  value       = local.spacelift_principal_account_id
}

output "spacelift_external_id_prefix" {
  description = "External ID prefix the role accepts. Spacelift's tokens look like <prefix>@<integration-id>@<stack-slug>@<read|write>."
  value       = "${var.spacelift_account_name}@"
}
