variable "name" {
  description = "Name prefix for every resource in this module, e.g. bookings-dev."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Needs room for 2 * az_count /20 subnets."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block, e.g. 10.20.0.0/16."
  }
}

variable "az_count" {
  description = "How many availability zones to spread subnets across."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 4
    error_message = "az_count must be between 2 and 4 (RDS needs at least two AZs for a subnet group)."
  }
}

variable "single_nat_gateway" {
  description = <<-EOT
    Route all private subnets through one NAT gateway instead of one per AZ.
    Cheap and fine for dev; in prod it makes a single AZ a hard dependency for
    all outbound traffic, so leave it false there.
  EOT
  type        = bool
  default     = false
}

variable "enable_interface_endpoints" {
  description = <<-EOT
    Create interface VPC endpoints for ECR, CloudWatch Logs and Secrets Manager.
    Fargate needs to reach those to pull images and ship logs; without endpoints
    that traffic goes out through NAT and is billed per GB. Endpoints cost a
    flat hourly rate per AZ, so it is a crossover: worth it in prod, usually not
    in a dev account that idles.
  EOT
  type        = bool
  default     = false
}

variable "enable_flow_logs" {
  description = "Publish VPC flow logs to CloudWatch Logs."
  type        = bool
  default     = false
}

variable "flow_log_retention_days" {
  description = "Retention for the VPC flow log group."
  type        = number
  default     = 30
}

variable "alb_ingress_cidrs" {
  description = "CIDRs allowed to reach the ALB on HTTP/HTTPS."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "container_port" {
  description = "Port the application container listens on; opened from the ALB to the service."
  type        = number
  default     = 80
}

variable "database_port" {
  description = "Port the database listens on; opened from the service to RDS."
  type        = number
  default     = 5432
}

variable "tags" {
  description = "Tags merged into every resource."
  type        = map(string)
  default     = {}
}

variable "alb_ingress_ports" {
  description = "Ports the ALB accepts from the internet. Add 443 once a certificate is attached."
  type        = list(number)
  default     = [80]
}
