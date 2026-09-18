output "alb_dns_name" {
  description = "Public entry point. Open this in a browser once the stack is applied."
  value       = module.ecs.alb_dns_name
}

output "ecs_cluster_name" {
  description = "ECS cluster name."
  value       = module.ecs.cluster_name
}

output "ecs_service_name" {
  description = "ECS service name."
  value       = module.ecs.service_name
}

output "log_group_name" {
  description = "CloudWatch log group for task logs."
  value       = module.ecs.log_group_name
}

output "rds_endpoint" {
  description = "Database endpoint. Private -- only resolvable and reachable from inside the VPC."
  value       = module.rds.endpoint
}

output "rds_master_user_secret_arn" {
  description = "Secrets Manager ARN for the master credentials, managed and rotated by RDS."
  value       = module.rds.master_user_secret_arn
}

output "vpc_id" {
  description = "VPC ID."
  value       = module.network.vpc_id
}
