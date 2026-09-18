# A single-writer PostgreSQL instance in private subnets.
#
# Two choices worth calling out:
#
#  * manage_master_user_password = true. RDS generates the password, stores it
#    in Secrets Manager and rotates it. The alternative -- random_password plus
#    an aws_secretsmanager_secret_version -- puts the plaintext password in the
#    Terraform state file forever, which is the most common way a database
#    credential leaks out of an otherwise careful setup.
#
#  * No publicly_accessible flag anywhere near true, and the subnet group only
#    contains private subnets. Combined with the security group (one ingress
#    rule, sourced from the ECS service group), there is no network path to this
#    instance from outside the VPC.

locals {
  tags = var.tags

  # A final snapshot is a one-line guard against a fat-fingered destroy. Naming
  # it with a timestamp avoids collisions with a snapshot from a previous run.
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name}-final-${formatdate("YYYYMMDDhhmmss", timestamp())}"
}

resource "aws_db_subnet_group" "this" {
  name        = "${var.name}-db"
  description = "Private subnets for ${var.name}"
  subnet_ids  = var.subnet_ids

  tags = merge(local.tags, { Name = "${var.name}-db" })
}

resource "aws_db_parameter_group" "this" {
  name        = "${var.name}-pg"
  family      = var.parameter_group_family
  description = "Logging and statistics defaults for ${var.name}"

  # Slow query log. Without this you find out about the missing index from a
  # customer rather than from CloudWatch.
  parameter {
    name  = "log_min_duration_statement"
    value = tostring(var.log_min_duration_statement)
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  # Log any statement that waits more than a second on a lock.
  parameter {
    name  = "log_lock_waits"
    value = "1"
  }

  # pg_stat_statements is how you find the query worth indexing. Requires a
  # reboot, hence pending-reboot rather than immediate.
  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements"
    apply_method = "pending-reboot"
  }

  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_iam_policy_document" "monitoring_assume_role" {
  count = var.monitoring_interval > 0 ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  name               = "${var.name}-rds-monitoring"
  assume_role_policy = data.aws_iam_policy_document.monitoring_assume_role[0].json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  role       = aws_iam_role.monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_db_instance" "this" {
  identifier = "${var.name}-db"

  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name  = var.database_name
  username = var.master_username
  port     = var.port

  # RDS owns the credential; Terraform only ever sees the secret ARN.
  manage_master_user_password = true

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = var.storage_type
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  parameter_group_name   = aws_db_parameter_group.this.name
  vpc_security_group_ids = var.security_group_ids
  publicly_accessible    = false
  multi_az               = var.multi_az

  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window
  copy_tags_to_snapshot   = true

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = local.final_snapshot_identifier

  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately          = var.apply_immediately

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_period : null

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.monitoring[0].arn : null

  # Ship the Postgres log to CloudWatch, otherwise the slow query log above is
  # only visible through the console's log file viewer.
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  tags = merge(local.tags, { Name = "${var.name}-db" })

  lifecycle {
    # timestamp() in the final snapshot name changes on every plan; without this
    # the instance would look like it needed replacing each time.
    ignore_changes = [final_snapshot_identifier]
  }
}
