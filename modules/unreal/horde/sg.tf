###########################################
# Horde External ALB Security Group
###########################################

resource "aws_security_group" "unreal_horde_external_alb_sg" {
  #checkov:skip=CKV2_AWS_5: SG attached to Horde external ALB
  count       = var.create_external_alb ? 1 : 0
  name        = "${local.name_prefix}-ext-ALB"
  vpc_id      = var.vpc_id
  description = "External Horde ALB Security Group."
  tags        = local.tags
}

resource "aws_vpc_security_group_egress_rule" "unreal_horde_external_alb_outbound_service_api" {
  count                        = var.create_external_alb ? 1 : 0
  security_group_id            = aws_security_group.unreal_horde_external_alb_sg[0].id
  description                  = "Allow outbound traffic from external Horde ALB to Horde host API."
  referenced_security_group_id = aws_security_group.unreal_horde_sg.id
  from_port                    = var.container_api_port
  to_port                      = var.container_api_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "unreal_horde_external_alb_outbound_service_grpc" {
  count                        = var.create_external_alb ? 1 : 0
  security_group_id            = aws_security_group.unreal_horde_external_alb_sg[0].id
  description                  = "Allow outbound traffic from external Horde ALB to Horde host gRPC port."
  referenced_security_group_id = aws_security_group.unreal_horde_sg.id
  from_port                    = var.container_grpc_port
  to_port                      = var.container_grpc_port
  ip_protocol                  = "tcp"
}

########################################
# Horde Host Security Group (was service SG)
########################################

resource "aws_security_group" "unreal_horde_sg" {
  #checkov:skip=CKV2_AWS_5: SG attached to Horde all-in-one EC2 host
  name        = "${local.name_prefix}-host"
  vpc_id      = var.vpc_id
  description = "Horde all-in-one EC2 host security group."
  tags        = local.tags
}

resource "aws_vpc_security_group_egress_rule" "unreal_horde_outbound_ipv4" {
  security_group_id = aws_security_group.unreal_horde_sg.id
  description       = "Allow outbound traffic from Horde host to the internet (ipv4)."
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_egress_rule" "unreal_horde_outbound_ipv6" {
  security_group_id = aws_security_group.unreal_horde_sg.id
  description       = "Allow outbound traffic from Horde host to the internet (ipv6)."
  cidr_ipv6         = "::/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "unreal_horde_inbound_external_alb_api" {
  count                        = var.create_external_alb ? 1 : 0
  security_group_id            = aws_security_group.unreal_horde_sg.id
  description                  = "Allow inbound API traffic from external Horde ALB."
  referenced_security_group_id = aws_security_group.unreal_horde_external_alb_sg[0].id
  from_port                    = var.container_api_port
  to_port                      = var.container_api_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "unreal_horde_inbound_external_alb_grpc" {
  count                        = var.create_external_alb ? 1 : 0
  security_group_id            = aws_security_group.unreal_horde_sg.id
  description                  = "Allow inbound gRPC traffic from external Horde ALB."
  referenced_security_group_id = aws_security_group.unreal_horde_external_alb_sg[0].id
  from_port                    = var.container_grpc_port
  to_port                      = var.container_grpc_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "unreal_horde_admin_ssh" {
  for_each = toset(var.admin_cidrs)

  security_group_id = aws_security_group.unreal_horde_sg.id
  description       = "Optional admin SSH from a trusted CIDR (SSM is preferred)."
  cidr_ipv4         = each.value
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

###########################################
# Horde Agents Security Group
###########################################

resource "aws_security_group" "unreal_horde_agent_sg" {
  #checkov:skip=CKV2_AWS_5: SG attached to Horde agent ASGs
  count       = length(var.agents) > 0 ? 1 : 0
  name        = "${local.name_prefix}-agents"
  vpc_id      = var.vpc_id
  description = "Horde agent EC2 instances security group."
  tags        = local.tags
}

resource "aws_vpc_security_group_egress_rule" "unreal_horde_agents_outbound_ipv4" {
  count             = length(var.agents) > 0 ? 1 : 0
  security_group_id = aws_security_group.unreal_horde_agent_sg[0].id
  description       = "Allow outbound traffic from Horde agents to the internet (ipv4)."
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_egress_rule" "unreal_horde_agents_outbound_ipv6" {
  count             = length(var.agents) > 0 ? 1 : 0
  security_group_id = aws_security_group.unreal_horde_agent_sg[0].id
  description       = "Allow outbound traffic from Horde agents to the internet (ipv6)."
  cidr_ipv6         = "::/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "unreal_horde_external_alb_inbound_agents" {
  count                        = var.create_external_alb && length(var.agents) > 0 ? 1 : 0
  security_group_id            = aws_security_group.unreal_horde_external_alb_sg[0].id
  description                  = "Allow agents to reach Horde via the external ALB on HTTPS."
  referenced_security_group_id = aws_security_group.unreal_horde_agent_sg[0].id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "unreal_horde_agents_inbound_agents" {
  count                        = length(var.agents) > 0 ? 1 : 0
  security_group_id            = aws_security_group.unreal_horde_agent_sg[0].id
  description                  = "Allow inbound traffic to Horde agents from peer agents."
  referenced_security_group_id = aws_security_group.unreal_horde_agent_sg[0].id
  from_port                    = 7000
  to_port                      = 7010
  ip_protocol                  = "tcp"
}
