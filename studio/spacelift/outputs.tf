output "phase1_stack_id" {
  description = "Spacelift stack ID for Phase 1 Perforce."
  value       = spacelift_stack.phase1_perforce.id
}

output "phase2_stack_id" {
  description = "Spacelift stack ID for Phase 2 Horde."
  value       = spacelift_stack.phase2_horde.id
}

output "aws_integration_id" {
  description = "Spacelift AWS integration ID."
  value       = spacelift_aws_integration.sidewinder.id
}
