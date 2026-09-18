# dev -- optimised for cost and iteration speed.
#
# The short version of what differs from prod: one NAT gateway instead of two,
# no standby, backups kept for a day, and nothing that stops `terraform destroy`
# from working, because this environment gets torn down regularly.

project     = "bookings"
environment = "dev"
aws_region  = "ap-south-1"

# --- network ---
vpc_cidr                   = "10.10.0.0/16"
az_count                   = 2
single_nat_gateway         = true  # ~$33/month saved; an AZ outage taking dev offline is acceptable
enable_interface_endpoints = false # NAT traffic in dev is small enough that endpoints cost more than they save
enable_flow_logs           = false

# --- application ---
container_image                = "public.ecr.aws/nginx/nginx:1.27-alpine"
task_cpu                       = 256
task_memory                    = 512
desired_count                  = 1
min_capacity                   = 1
max_capacity                   = 2
log_retention_days             = 7
enable_container_insights      = false
enable_execute_command         = true # shelling into a dev task is routine
enable_alb_deletion_protection = false

# --- database ---
db_instance_class               = "db.t4g.micro"
db_allocated_storage            = 20
db_max_allocated_storage        = 50
db_engine_version               = "16.4"
db_multi_az                     = false
db_backup_retention_period      = 1
db_deletion_protection          = false
db_skip_final_snapshot          = true
db_performance_insights_enabled = false
db_monitoring_interval          = 0
db_apply_immediately            = true
