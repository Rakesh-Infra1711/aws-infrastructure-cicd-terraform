variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Short project name used as a prefix for all resources (must match the bootstrap stack)"
  type        = string
  default     = "devops-task"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

# ---------------- Networking ----------------
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "az_count" {
  description = "Number of Availability Zones to spread subnets across"
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "Use 2 or 3 AZs; the ALB and RDS subnet group need at least 2."
  }
}

variable "single_nat_gateway" {
  description = "true = one shared NAT Gateway (lower cost). false = one NAT per AZ (production HA)"
  type        = bool
  default     = true
}

# ---------------- DNS / TLS ----------------
variable "domain_name" {
  description = "Fully qualified domain for the application, e.g. app.example.com"
  type        = string
}

variable "route53_zone_id" {
  description = "Route 53 hosted zone ID for the domain. Leave empty if DNS is hosted elsewhere (e.g. GoDaddy); then add the ACM validation and app CNAME records manually."
  type        = string
  default     = ""
}

# ---------------- Compute ----------------
variable "instance_type" {
  description = "EC2 instance type for the application"
  type        = string
  default     = "t3.micro"
}

variable "asg_min_size" {
  type    = number
  default = 2
}

variable "asg_max_size" {
  type    = number
  default = 4
}

variable "asg_desired_capacity" {
  type    = number
  default = 2
}

variable "app_port" {
  description = "Port the application listens on inside the instances"
  type        = number
  default     = 8080
}

# ---------------- Database ----------------
variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_name" {
  type    = string
  default = "appdb"
}

variable "db_username" {
  description = "Master username. The password is generated and stored by RDS in Secrets Manager."
  type        = string
  default     = "appadmin"
}

variable "db_multi_az" {
  description = "Enable Multi-AZ standby for RDS (recommended for production, doubles DB cost)"
  type        = bool
  default     = false
}

variable "db_backup_retention_days" {
  description = "Days of automated RDS backups (point-in-time recovery). AWS Free plan accounts allow only 1."
  type        = number
  default     = 7

  validation {
    condition     = var.db_backup_retention_days >= 0 && var.db_backup_retention_days <= 35
    error_message = "Backup retention must be between 0 and 35 days."
  }
}

variable "db_max_allocated_storage" {
  description = "Upper limit in GiB for RDS storage autoscaling. 0 disables autoscaling (needed on the AWS Free plan)."
  type        = number
  default     = 50
}

variable "db_deletion_protection" {
  description = "Protect the database from accidental deletion"
  type        = bool
  default     = false
}

# ---------------- Logging ----------------
variable "alb_log_retention_days" {
  type    = number
  default = 90
}
