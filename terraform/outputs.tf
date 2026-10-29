output "app_url" {
  description = "Public HTTPS URL of the application"
  value       = "https://${var.domain_name}"
}

output "alb_dns_name" {
  description = "ALB DNS name. Without Route 53, create a CNAME from domain_name to this value."
  value       = aws_lb.this.dns_name
}

output "acm_validation_records" {
  description = "DNS records to add at your DNS provider to validate the ACM certificate (only needed without Route 53)"
  value = [for dvo in aws_acm_certificate.app.domain_validation_options : {
    name  = dvo.resource_record_name
    type  = dvo.resource_record_type
    value = dvo.resource_record_value
  }]
}

output "vpc_id" {
  value = aws_vpc.this.id
}

output "asg_name" {
  value = aws_autoscaling_group.app.name
}

output "target_group_arn" {
  value = aws_lb_target_group.app.arn
}

output "rds_endpoint" {
  value = aws_db_instance.this.address
}

output "db_secret_arn" {
  description = "Secrets Manager secret holding the RDS master credentials"
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "app_bucket" {
  value = aws_s3_bucket.app.id
}

output "alb_logs_bucket" {
  value = aws_s3_bucket.alb_logs.id
}

output "app_version" {
  description = "Hash of the deployed application code"
  value       = local.app_version
}
