# The S3 gateway endpoint is free and always worth having: ECR stores image
# layers in S3, so without it every task start pulls its layers out through the
# NAT gateway and you pay per-GB for bytes that never leave the region.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id

  tags = merge(local.tags, { Name = "${var.name}-s3" })
}

data "aws_region" "current" {}

locals {
  interface_endpoints = var.enable_interface_endpoints ? toset([
    "ecr.api",        # authorisation and manifest calls
    "ecr.dkr",        # the docker registry protocol itself
    "logs",           # awslogs driver
    "secretsmanager", # database credentials injected into the task
    "ssmmessages",    # ECS Exec
  ]) : toset([])
}

resource "aws_security_group" "vpc_endpoints" {
  count = var.enable_interface_endpoints ? 1 : 0

  name        = "${var.name}-vpc-endpoints"
  description = "Interface VPC endpoints for ${var.name}"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name}-vpc-endpoints" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_from_service" {
  count = var.enable_interface_endpoints ? 1 : 0

  security_group_id            = aws_security_group.vpc_endpoints[0].id
  description                  = "HTTPS from the ECS service"
  referenced_security_group_id = aws_security_group.service.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoints

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(local.tags, { Name = "${var.name}-${each.value}" })
}
