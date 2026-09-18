variable "name" {
  description = "Name prefix, e.g. bookings-dev."
  type        = string
}

variable "vpc_id" {
  description = "VPC the cluster and load balancer live in."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets for the ALB."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnets for the Fargate tasks."
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security group for the load balancer, created by the network module."
  type        = string
}

variable "service_security_group_id" {
  description = "Security group for the tasks, created by the network module."
  type        = string
}

variable "container_image" {
  description = "Image to run. A placeholder web server is enough to prove the path from the ALB works."
  type        = string
  default     = "public.ecr.aws/nginx/nginx:1.27-alpine"
}

variable "container_name" {
  description = "Container name inside the task definition; also the target of the ALB attachment."
  type        = string
  default     = "app"
}

variable "container_port" {
  description = "Port the container listens on."
  type        = number
  default     = 80
}

variable "task_cpu" {
  description = "Fargate CPU units for the task (256 = 0.25 vCPU)."
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Fargate memory in MiB. Valid values depend on task_cpu."
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Tasks to run. Also the starting point for autoscaling."
  type        = number
  default     = 1
}

variable "min_capacity" {
  description = "Autoscaling floor."
  type        = number
  default     = 1
}

variable "max_capacity" {
  description = "Autoscaling ceiling."
  type        = number
  default     = 4
}

variable "cpu_target_value" {
  description = "Average CPU percentage the target-tracking policy aims to hold."
  type        = number
  default     = 60
}

variable "health_check_path" {
  description = "Path the target group polls."
  type        = string
  default     = "/"
}

variable "health_check_matcher" {
  description = "HTTP status codes counted as healthy."
  type        = string
  default     = "200-399"
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for the task log group. Never leave this at 'never expire'."
  type        = number
  default     = 30
}

variable "enable_container_insights" {
  description = "Container Insights gives per-task CPU/memory metrics. Costs extra."
  type        = bool
  default     = false
}

variable "enable_deletion_protection" {
  description = "Stop the load balancer being deleted by accident."
  type        = bool
  default     = false
}

variable "enable_execute_command" {
  description = "Allow `aws ecs execute-command` into a running task. Handy in dev, audited in prod."
  type        = bool
  default     = false
}

variable "container_environment" {
  description = "Plain environment variables for the container."
  type        = map(string)
  default     = {}
}

variable "container_secrets" {
  description = <<-EOT
    Secrets injected at start-up, as name => Secrets Manager or SSM ARN. Values
    are resolved by the ECS agent, so they never appear in the task definition
    or in `terraform show`.
  EOT
  type        = map(string)
  default     = {}
}

variable "deregistration_delay" {
  description = "Seconds the ALB waits for in-flight requests before removing a target."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags merged into every resource."
  type        = map(string)
  default     = {}
}
