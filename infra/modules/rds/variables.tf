variable "name" {
  description = "Name prefix, e.g. bookings-dev."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets for the DB subnet group. At least two AZs."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "RDS requires a subnet group spanning at least two availability zones."
  }
}

variable "security_group_ids" {
  description = "Security groups to attach. Expected to allow ingress only from the application tier."
  type        = list(string)
}

variable "engine_version" {
  description = "PostgreSQL major.minor version. Kept in step with the local docker-compose image."
  type        = string
  default     = "16.4"
}

variable "parameter_group_family" {
  description = "Parameter group family; must match the engine major version."
  type        = string
  default     = "postgres16"
}

variable "instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Initial storage in GiB."
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Upper bound for storage autoscaling. Set equal to allocated_storage to disable it."
  type        = number
  default     = 100
}

variable "storage_type" {
  description = "gp3 unless there is a reason not to; it decouples IOPS from volume size."
  type        = string
  default     = "gp3"
}

variable "database_name" {
  description = "Name of the initial database."
  type        = string
  default     = "bookings"
}

variable "master_username" {
  description = "Master username. The password is generated and rotated by RDS, never stored in Terraform state."
  type        = string
  default     = "bookings_admin"
}

variable "port" {
  description = "Port the instance listens on."
  type        = number
  default     = 5432
}

variable "multi_az" {
  description = "Run a synchronous standby in a second AZ."
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Days of automated backups. 0 disables them, which also disables PITR."
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_period >= 1 && var.backup_retention_period <= 35
    error_message = "Keep at least one day of backups; 35 is the RDS maximum."
  }
}

variable "backup_window" {
  description = "Daily UTC window for automated backups."
  type        = string
  default     = "17:00-18:00"
}

variable "maintenance_window" {
  description = "Weekly UTC window for patching. Must not overlap backup_window."
  type        = string
  default     = "sun:18:30-sun:19:30"
}

variable "deletion_protection" {
  description = "Refuse to delete the instance until this is turned off."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot on destroy. Only ever true in a throwaway environment."
  type        = bool
  default     = false
}

variable "apply_immediately" {
  description = "Apply changes now instead of waiting for the maintenance window."
  type        = bool
  default     = false
}

variable "performance_insights_enabled" {
  description = "Enable Performance Insights."
  type        = bool
  default     = true
}

variable "performance_insights_retention_period" {
  description = "Days of Performance Insights history. 7 is the free tier."
  type        = number
  default     = 7
}

variable "monitoring_interval" {
  description = "Enhanced monitoring granularity in seconds. 0 disables it."
  type        = number
  default     = 0

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval must be one of 0, 1, 5, 10, 15, 30, 60."
  }
}

variable "log_min_duration_statement" {
  description = "Log statements slower than this many milliseconds. -1 disables slow query logging."
  type        = number
  default     = 1000
}

variable "auto_minor_version_upgrade" {
  description = "Let RDS apply minor version patches during the maintenance window."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags merged into every resource."
  type        = map(string)
  default     = {}
}
