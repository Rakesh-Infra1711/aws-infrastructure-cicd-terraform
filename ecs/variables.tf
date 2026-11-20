variable "aws_region" {
  description = "AWS region for the container stack"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Short name used as a prefix for resource names"
  type        = string
  default     = "devops-task"
}

variable "github_repository" {
  description = "GitHub repository allowed to deploy, as owner/name"
  type        = string
  default     = "Rakesh-Infra1711/aws-infrastructure-cicd-terraform"
}

variable "create_github_oidc_provider" {
  description = "Create the GitHub OIDC provider. Set false if it already exists in the account (one per account)."
  type        = bool
  default     = true
}

variable "allowed_cidr" {
  description = "CIDR allowed to reach the app on port 8080. Use your own IP/32 to keep the demo private."
  type        = string
  default     = "0.0.0.0/0"
}

variable "task_cpu" {
  description = "Fargate task CPU units (256 = 0.25 vCPU)"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Fargate task memory in MiB"
  type        = number
  default     = 512
}

variable "log_retention_days" {
  description = "CloudWatch log retention for container logs"
  type        = number
  default     = 7
}
