variable "project" {
  description = "Project name, used as the first part of every resource name."
  type        = string
  default     = "bookings"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "Region to deploy into."
  type        = string
  default     = "ap-south-1"
}

# --- network -----------------------------------------------------------------

variable "vpc_cidr" {
  description = "VPC CIDR. Dev and prod do not overlap, so the two can be peered later if needed."
  type        = string
}

variable "az_count" {
  description = "Number of availability zones."
  type        = number
}

variable "single_nat_gateway" {
  description = "Share one NAT gateway across all private subnets."
  type        = bool
}

variable "enable_interface_endpoints" {
  description = "Create interface VPC endpoints for ECR/Logs/Secrets Manager."
  type        = bool
}

variable "enable_flow_logs" {
  description = "Send VPC flow logs to CloudWatch."
  type        = bool
}

# --- application -------------------------------------------------------------

variable "container_image" {
  description = "Container image for the application service."
  type        = string
}

variable "task_cpu" {
  description = "Fargate CPU units per task."
  type        = number
}

variable "task_memory" {
  description = "Fargate memory (MiB) per task."
  type        = number
}

variable "desired_count" {
  description = "Initial task count."
  type        = number
}

variable "min_capacity" {
  description = "Autoscaling floor."
  type        = number
}

variable "max_capacity" {
  description = "Autoscaling ceiling."
  type        = number
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for task logs."
  type        = number
}

variable "enable_container_insights" {
  description = "Enable ECS Container Insights."
  type        = bool
}

variable "enable_execute_command" {
  description = "Allow ECS Exec into running tasks."
  type        = bool
}

variable "enable_alb_deletion_protection" {
  description = "Protect the load balancer from deletion."
  type        = bool
}

# --- database ----------------------------------------------------------------

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
}

variable "db_allocated_storage" {
  description = "Initial RDS storage (GiB)."
  type        = number
}

variable "db_max_allocated_storage" {
  description = "Storage autoscaling ceiling (GiB)."
  type        = number
}

variable "db_engine_version" {
  description = "PostgreSQL version."
  type        = string
}

variable "db_multi_az" {
  description = "Run a standby in a second AZ."
  type        = bool
}

variable "db_backup_retention_period" {
  description = "Days of automated backups."
  type        = number
}

variable "db_deletion_protection" {
  description = "Protect the database from deletion."
  type        = bool
}

variable "db_skip_final_snapshot" {
  description = "Skip the final snapshot when the instance is destroyed."
  type        = bool
}

variable "db_performance_insights_enabled" {
  description = "Enable Performance Insights."
  type        = bool
}

variable "db_monitoring_interval" {
  description = "Enhanced monitoring interval in seconds; 0 disables it."
  type        = number
}

variable "db_apply_immediately" {
  description = "Apply database changes immediately instead of during the maintenance window."
  type        = bool
}
