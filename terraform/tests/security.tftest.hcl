# Offline policy tests: "apply" the full stack against a mocked AWS provider and
# assert the security requirements. Run with:  terraform test
# No AWS account or credentials are needed.

mock_provider "aws" {
  # Realistic ARNs so the provider's ARN validation accepts mocked values
  mock_resource "aws_lb" {
    defaults = {
      arn      = "arn:aws:elasticloadbalancing:ap-south-1:123456789012:loadbalancer/app/mock/0123456789abcdef"
      dns_name = "mock-alb-123.ap-south-1.elb.amazonaws.com"
      zone_id  = "ZP97RAFLXTNZK"
    }
  }
  mock_resource "aws_lb_target_group" {
    defaults = { arn = "arn:aws:elasticloadbalancing:ap-south-1:123456789012:targetgroup/mock/0123456789abcdef" }
  }
  mock_resource "aws_acm_certificate" {
    defaults = { arn = "arn:aws:acm:ap-south-1:123456789012:certificate/00000000-0000-0000-0000-000000000000" }
  }
  mock_resource "aws_iam_instance_profile" {
    defaults = { arn = "arn:aws:iam::123456789012:instance-profile/mock" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/mock" }
  }
  mock_resource "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::mock-bucket" }
  }
  mock_resource "aws_launch_template" {
    defaults = { id = "lt-0123456789abcdef0", latest_version = 1 }
  }

  override_data {
    target = data.aws_availability_zones.available
    values = { names = ["ap-south-1a", "ap-south-1b", "ap-south-1c"] }
  }
  override_data {
    target = data.aws_caller_identity.current
    values = { account_id = "123456789012" }
  }
  override_data {
    target = data.aws_ssm_parameter.al2023
    values = { insecure_value = "ami-0123456789abcdef0", value = "ami-0123456789abcdef0" }
  }
  override_data {
    target = data.aws_elb_service_account.this
    values = { arn = "arn:aws:iam::718504428378:root" }
  }
  override_data {
    target = data.aws_iam_policy_document.ec2_assume
    values = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  override_data {
    target = data.aws_iam_policy_document.app
    values = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  override_resource {
    target = aws_db_instance.this
    values = {
      address            = "devops-task-prod-mysql.abc.ap-south-1.rds.amazonaws.com"
      master_user_secret = [{ secret_arn = "arn:aws:secretsmanager:ap-south-1:123456789012:secret:rds!db-test", kms_key_id = "", secret_status = "active" }]
    }
  }
  override_resource {
    target = aws_acm_certificate_validation.app
    values = { certificate_arn = "arn:aws:acm:ap-south-1:123456789012:certificate/test" }
  }
}

variables {
  domain_name = "devops-task.example.com"
}

run "network_layout" {
  command = apply

  assert {
    condition     = length(aws_subnet.public) == 2 && length(aws_subnet.app) == 2 && length(aws_subnet.db) == 2
    error_message = "Expected 2 public, 2 app and 2 db subnets"
  }
  assert {
    condition     = aws_subnet.app[0].availability_zone != aws_subnet.app[1].availability_zone
    error_message = "App subnets must be in different AZs"
  }
  assert {
    condition     = length(aws_nat_gateway.this) == 1
    error_message = "Default should use a single NAT Gateway"
  }
  assert {
    condition     = length(aws_route_table.db.route) == 0
    error_message = "Database subnets must have no route to the internet"
  }
}

run "database_is_private_and_encrypted" {
  command = apply

  assert {
    condition     = aws_db_instance.this.publicly_accessible == false
    error_message = "RDS must not be publicly accessible"
  }
  assert {
    condition     = aws_db_instance.this.storage_encrypted == true
    error_message = "RDS storage must be encrypted"
  }
  assert {
    condition     = aws_db_instance.this.manage_master_user_password == true
    error_message = "DB password must be managed in Secrets Manager"
  }
  assert {
    condition     = one([for p in aws_db_parameter_group.this.parameter : p.value if p.name == "require_secure_transport"]) == "1"
    error_message = "RDS must require TLS connections"
  }
}

run "https_only" {
  command = apply

  assert {
    condition     = aws_lb_listener.http.default_action[0].type == "redirect" && aws_lb_listener.http.default_action[0].redirect[0].protocol == "HTTPS"
    error_message = "HTTP listener must redirect to HTTPS"
  }
  assert {
    condition     = aws_lb_listener.https.protocol == "HTTPS" && startswith(aws_lb_listener.https.ssl_policy, "ELBSecurityPolicy-TLS13")
    error_message = "HTTPS listener must use a TLS 1.2+/1.3 policy"
  }
  assert {
    condition     = aws_lb.this.access_logs[0].enabled == true
    error_message = "ALB access logs must be enabled"
  }
}

run "instances_hardened" {
  command = apply

  assert {
    condition     = aws_launch_template.app.metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 must be required"
  }
  assert {
    condition     = aws_launch_template.app.block_device_mappings[0].ebs[0].encrypted == "true"
    error_message = "EBS root volume must be encrypted"
  }
  assert {
    condition     = aws_autoscaling_group.app.health_check_type == "ELB"
    error_message = "ASG must use ALB health checks"
  }
}

run "buckets_private" {
  command = apply

  assert {
    condition     = aws_s3_bucket_public_access_block.app.block_public_acls && aws_s3_bucket_public_access_block.app.restrict_public_buckets
    error_message = "App bucket must block public access"
  }
  assert {
    condition     = aws_s3_bucket_public_access_block.alb_logs.block_public_policy
    error_message = "ALB log bucket must block public access"
  }
}

run "production_mode" {
  command = apply

  variables {
    single_nat_gateway     = false
    db_multi_az            = true
    db_deletion_protection = true
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 2
    error_message = "Production mode should create one NAT Gateway per AZ"
  }
  assert {
    condition     = aws_db_instance.this.multi_az && aws_db_instance.this.deletion_protection
    error_message = "Production mode should enable Multi-AZ and deletion protection"
  }
}
