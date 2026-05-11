output "spacelift_oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider for Spacelift. Reference this when adding more stacks later."
  value       = aws_iam_openid_connect_provider.spacelift.arn
}

output "spacelift_runner_role_arn" {
  description = "ARN of the IAM role Spacelift assumes. Paste into the admin stack's spacelift_aws_integration resource."
  value       = aws_iam_role.spacelift_runner.arn
}

output "spacelift_runner_role_name" {
  description = "Name of the IAM role Spacelift assumes."
  value       = aws_iam_role.spacelift_runner.name
}
