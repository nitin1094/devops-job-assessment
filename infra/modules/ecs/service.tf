resource "aws_ecs_service" "this" {
  name            = var.name
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count

  launch_type            = "FARGATE"
  platform_version       = "LATEST"
  enable_execute_command = var.enable_execute_command

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.service_security_group_id]
    assign_public_ip = false # tasks reach the internet through the NAT gateway
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = var.container_name
    container_port   = var.container_port
  }

  # Give the container a minute to come up before the ALB starts failing it.
  health_check_grace_period_seconds = 60

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  # If a new task definition never reaches a steady state, roll back to the
  # previous one instead of retrying forever with the service half down.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  propagate_tags = "SERVICE"
  tags           = var.tags

  lifecycle {
    # desired_count is owned by application autoscaling once the service is
    # running; Terraform should not drag it back to the configured value on
    # every apply.
    ignore_changes = [desired_count]
  }

  depends_on = [aws_lb_listener.http]
}
