# prod -- optimised for availability and recoverability.
#
# Differences from dev, and why:
#   two NAT gateways         a single one makes one AZ a dependency for all egress
#   multi-AZ database        automatic failover instead of a restore-from-backup
#   30 days of backups       gives a real point-in-time recovery window
#   deletion protection on   on both the database and the load balancer
#   final snapshot kept      destroy is never the last word on the data
#   interface endpoints      at prod traffic volumes they are cheaper than NAT
#   no ECS Exec              shell access to prod tasks goes through a break-glass
#                            role, not a flag that is on by default

project     = "bookings"
environment = "prod"
aws_region  = "ap-south-1"

# --- network ---
vpc_cidr                   = "10.20.0.0/16"
az_count                   = 3
single_nat_gateway         = false
enable_interface_endpoints = true
enable_flow_logs           = true

# --- application ---
container_image                = "public.ecr.aws/nginx/nginx:1.27-alpine"
task_cpu                       = 1024
task_memory                    = 2048
desired_count                  = 3
min_capacity                   = 3
max_capacity                   = 12
log_retention_days             = 90
enable_container_insights      = true
enable_execute_command         = false
enable_alb_deletion_protection = true

# --- database ---
db_instance_class               = "db.r7g.large"
db_allocated_storage            = 100
db_max_allocated_storage        = 1000
db_engine_version               = "16.4"
db_multi_az                     = true
db_backup_retention_period      = 30
db_deletion_protection          = true
db_skip_final_snapshot          = false
db_performance_insights_enabled = true
db_monitoring_interval          = 30
db_apply_immediately            = false
