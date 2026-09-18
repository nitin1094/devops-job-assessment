# dev environment.
#
# Same modules as prod, different numbers. Anything that differs between the two
# is a variable in terraform.tfvars -- there are no `count = var.environment ==
# "prod"` conditionals in the modules, because that is how the two environments
# quietly drift apart until prod is the only one anybody trusts.

locals {
  name = "${var.project}-${var.environment}"
}

module "network" {
  source = "../../modules/network"

  name                       = local.name
  vpc_cidr                   = var.vpc_cidr
  az_count                   = var.az_count
  single_nat_gateway         = var.single_nat_gateway
  enable_interface_endpoints = var.enable_interface_endpoints
  enable_flow_logs           = var.enable_flow_logs
  container_port             = 80
  database_port              = 5432
}

module "rds" {
  source = "../../modules/rds"

  name               = local.name
  subnet_ids         = module.network.private_subnet_ids
  security_group_ids = [module.network.database_security_group_id]

  engine_version         = var.db_engine_version
  parameter_group_family = "postgres${split(".", var.db_engine_version)[0]}"
  instance_class         = var.db_instance_class
  allocated_storage      = var.db_allocated_storage
  max_allocated_storage  = var.db_max_allocated_storage
  database_name          = "bookings"

  multi_az                = var.db_multi_az
  backup_retention_period = var.db_backup_retention_period
  deletion_protection     = var.db_deletion_protection
  skip_final_snapshot     = var.db_skip_final_snapshot

  performance_insights_enabled = var.db_performance_insights_enabled
  monitoring_interval          = var.db_monitoring_interval

  # dev applies changes straight away; prod waits for the maintenance window so
  # a parameter change cannot trigger a reboot in the middle of the day.
  apply_immediately = var.db_apply_immediately
}

module "ecs" {
  source = "../../modules/ecs"

  name                      = local.name
  vpc_id                    = module.network.vpc_id
  public_subnet_ids         = module.network.public_subnet_ids
  private_subnet_ids        = module.network.private_subnet_ids
  alb_security_group_id     = module.network.alb_security_group_id
  service_security_group_id = module.network.service_security_group_id

  container_image = var.container_image
  container_port  = 80
  task_cpu        = var.task_cpu
  task_memory     = var.task_memory

  desired_count = var.desired_count
  min_capacity  = var.min_capacity
  max_capacity  = var.max_capacity

  log_retention_days         = var.log_retention_days
  enable_container_insights  = var.enable_container_insights
  enable_execute_command     = var.enable_execute_command
  enable_deletion_protection = var.enable_alb_deletion_protection

  # Host and port are not secret; the credential is. The task resolves
  # DB_CREDENTIALS from Secrets Manager at start-up, so the password never
  # exists in the task definition, in state, or in `terraform show` output.
  container_environment = {
    DB_HOST = module.rds.address
    DB_PORT = tostring(module.rds.port)
    DB_NAME = module.rds.database_name
    APP_ENV = var.environment
  }

  container_secrets = {
    DB_CREDENTIALS = module.rds.master_user_secret_arn
  }
}
