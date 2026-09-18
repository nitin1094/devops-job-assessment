output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnets, one per AZ. The ALB lives here."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnets, one per AZ. Fargate tasks and RDS live here."
  value       = aws_subnet.private[*].id
}

output "availability_zones" {
  description = "AZs the subnets were placed in."
  value       = local.azs
}

output "alb_security_group_id" {
  description = "Security group for the load balancer."
  value       = aws_security_group.alb.id
}

output "service_security_group_id" {
  description = "Security group for the Fargate service."
  value       = aws_security_group.service.id
}

output "database_security_group_id" {
  description = "Security group for RDS. Only the service security group can reach it."
  value       = aws_security_group.database.id
}
