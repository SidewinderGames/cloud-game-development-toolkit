###############################################################
# Agent -> P4 server ingress rule
#
# The Horde agent ASG instances need TCP 1666 (Perforce) reachable
# to sync workspaces. P4's "sidewinder-p4-user-access" SG is owned
# by Phase 1; we look it up and attach an ingress rule scoped to
# this stack's agent SG so the dependency lives with the consumer.
#
# This keeps Phase 1 ignorant of Phase 2 SG IDs and avoids any
# admin-stack passthrough variables.
###############################################################

data "aws_security_group" "p4_user_access" {
  filter {
    name   = "group-name"
    values = ["sidewinder-p4-user-access"]
  }
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
}

resource "aws_vpc_security_group_ingress_rule" "agent_to_p4" {
  count = module.horde.agent_security_group_id == null ? 0 : 1

  security_group_id            = data.aws_security_group.p4_user_access.id
  referenced_security_group_id = module.horde.agent_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 1666
  to_port                      = 1666
  description                  = "Horde agent ASG to P4 commit (Phase 2 -> Phase 1)"

  tags = var.tags
}
