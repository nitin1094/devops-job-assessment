# Three groups, one chain:
#
#   internet --80--> [alb] --container_port--> [service] --5432--> [rds]
#
# Every rule below names a security group as its source or destination rather
# than a CIDR, so the rules keep working when subnets or task IPs change, and
# RDS is reachable from exactly one place: a task running in this service.

locals {
  alb_ingress_rules = {
    for pair in setproduct(var.alb_ingress_ports, var.alb_ingress_cidrs) :
    "${pair[0]}-${pair[1]}" => { port = pair[0], cidr = pair[1] }
  }
}

# --- ALB ---------------------------------------------------------------------

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "Public entry point for ${var.name}"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name}-alb" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_public" {
  for_each = local.alb_ingress_rules

  security_group_id = aws_security_group.alb.id
  description       = "Inbound HTTP(S) from ${each.value.cidr}"
  cidr_ipv4         = each.value.cidr
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
}

resource "aws_vpc_security_group_egress_rule" "alb_to_service" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Forward requests and health checks to the ECS service"
  referenced_security_group_id = aws_security_group.service.id
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
}

# --- ECS / Fargate service ---------------------------------------------------

resource "aws_security_group" "service" {
  name        = "${var.name}-service"
  description = "Fargate tasks for ${var.name}"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name}-service" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "service_from_alb" {
  security_group_id            = aws_security_group.service.id
  description                  = "Application traffic from the load balancer only"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
}

# Egress is enumerated rather than left wide open. Note that image pulls and log
# shipping go out over the *task* ENI, so 443 and DNS are not optional even for
# a container that makes no outbound calls of its own.
resource "aws_vpc_security_group_egress_rule" "service_https" {
  security_group_id = aws_security_group.service.id
  description       = "ECR image pulls, CloudWatch Logs, Secrets Manager, and outbound API calls"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "service_dns_udp" {
  security_group_id = aws_security_group.service.id
  description       = "DNS to the VPC resolver"
  cidr_ipv4         = aws_vpc.this.cidr_block
  ip_protocol       = "udp"
  from_port         = 53
  to_port           = 53
}

resource "aws_vpc_security_group_egress_rule" "service_dns_tcp" {
  security_group_id = aws_security_group.service.id
  description       = "DNS over TCP for responses that do not fit in a UDP packet"
  cidr_ipv4         = aws_vpc.this.cidr_block
  ip_protocol       = "tcp"
  from_port         = 53
  to_port           = 53
}

resource "aws_vpc_security_group_egress_rule" "service_to_database" {
  security_group_id            = aws_security_group.service.id
  description                  = "Database connections"
  referenced_security_group_id = aws_security_group.database.id
  ip_protocol                  = "tcp"
  from_port                    = var.database_port
  to_port                      = var.database_port
}

# --- RDS ---------------------------------------------------------------------

resource "aws_security_group" "database" {
  name        = "${var.name}-database"
  description = "RDS for ${var.name}; reachable only from the ECS service"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name}-database" })

  lifecycle {
    create_before_destroy = true
  }
}

# The only ingress rule this group will ever have. No bastion, no office CIDR,
# no "temporarily" opened 5432 -- reaching the database means going through a
# task, which means going through the load balancer.
resource "aws_vpc_security_group_ingress_rule" "database_from_service" {
  security_group_id            = aws_security_group.database.id
  description                  = "PostgreSQL from the ECS service"
  referenced_security_group_id = aws_security_group.service.id
  ip_protocol                  = "tcp"
  from_port                    = var.database_port
  to_port                      = var.database_port
}

# Deliberately no egress rules: RDS does not need to originate connections, and
# an aws_security_group with no egress blocks has its default allow-all rule
# removed by Terraform.
