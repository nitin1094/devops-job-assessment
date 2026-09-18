output "cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.this.name
}

output "cluster_arn" {
  description = "ECS cluster ARN."
  value       = aws_ecs_cluster.this.arn
}

output "service_name" {
  description = "ECS service name."
  value       = aws_ecs_service.this.name
}

output "task_definition_arn" {
  description = "ARN of the current task definition revision."
  value       = aws_ecs_task_definition.this.arn
}

output "task_role_arn" {
  description = "Runtime IAM role for the application."
  value       = aws_iam_role.task.arn
}

output "alb_dns_name" {
  description = "Public DNS name of the load balancer -- the entry point for the whole stack."
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Hosted zone of the ALB, for a Route 53 alias record."
  value       = aws_lb.this.zone_id
}

output "target_group_arn" {
  description = "ARN of the target group."
  value       = aws_lb_target_group.this.arn
}

output "log_group_name" {
  description = "CloudWatch log group the tasks write to."
  value       = aws_cloudwatch_log_group.this.name
}
