output "instance_identifier" {
  description = "RDS instance identifier."
  value       = aws_db_instance.this.identifier
}

output "endpoint" {
  description = "Connection endpoint, host:port."
  value       = aws_db_instance.this.endpoint
}

output "address" {
  description = "Hostname of the instance."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "Port the instance listens on."
  value       = aws_db_instance.this.port
}

output "database_name" {
  description = "Name of the initial database."
  value       = aws_db_instance.this.db_name
}

output "master_user_secret_arn" {
  description = <<-EOT
    ARN of the Secrets Manager secret holding the master credentials. Pass this
    to the ECS task definition as a secret reference so the password is never
    rendered into a task definition or an environment variable.
  EOT
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}
