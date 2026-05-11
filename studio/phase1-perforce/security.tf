resource "aws_security_group" "p4_user_access" {
  name        = "${local.project_prefix}-p4-user-access"
  description = "Allow developer workstations to reach the P4 server on TCP/1666."
  vpc_id      = aws_vpc.studio.id

  tags = {
    Name = "${local.project_prefix}-p4-user-access"
  }
}

resource "aws_vpc_security_group_ingress_rule" "p4_user_1666" {
  for_each = toset(var.allowed_p4_cidrs)

  security_group_id = aws_security_group.p4_user_access.id
  description       = "Allow Perforce traffic from a developer CIDR."
  ip_protocol       = "tcp"
  from_port         = 1666
  to_port           = 1666
  cidr_ipv4         = each.value
}
