# Offline tests for the container stack: "apply" against a mocked AWS provider
# and check the security and reliability settings. Run from ecs/:  terraform test
# No AWS account or credentials are needed.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_subnets" {
    defaults = { ids = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0aaaaaaaaaaaaaaa2"] }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/mock" }
  }
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com" }
  }
  mock_resource "aws_ecr_repository" {
    defaults = {
      arn            = "arn:aws:ecr:ap-south-1:123456789012:repository/devops-task-app"
      repository_url = "123456789012.dkr.ecr.ap-south-1.amazonaws.com/devops-task-app"
    }
  }
  mock_resource "aws_ecs_cluster" {
    defaults = { arn = "arn:aws:ecs:ap-south-1:123456789012:cluster/devops-task-cluster" }
  }
  mock_resource "aws_ecs_task_definition" {
    defaults = { arn = "arn:aws:ecs:ap-south-1:123456789012:task-definition/devops-task-app:1" }
  }
}

run "ecr_images_are_immutable_and_scanned" {
  command = apply

  assert {
    condition     = aws_ecr_repository.app.image_tag_mutability == "IMMUTABLE"
    error_message = "Image tags must be immutable so a commit SHA always points to the same image."
  }
  assert {
    condition     = aws_ecr_repository.app.image_scanning_configuration[0].scan_on_push
    error_message = "ECR must scan every pushed image for vulnerabilities."
  }
}

run "service_rolls_back_failed_deployments" {
  command = apply

  assert {
    condition     = aws_ecs_service.app.deployment_circuit_breaker[0].enable && aws_ecs_service.app.deployment_circuit_breaker[0].rollback
    error_message = "The deployment circuit breaker must roll back failed deployments."
  }
  assert {
    condition     = aws_ecs_service.app.deployment_minimum_healthy_percent == 100
    error_message = "Old tasks must keep serving until new ones are healthy (zero downtime)."
  }
}

run "only_the_app_port_is_open" {
  command = apply

  assert {
    condition     = length(aws_security_group.task.ingress) == 1 && one(aws_security_group.task.ingress).from_port == 8080 && one(aws_security_group.task.ingress).to_port == 8080
    error_message = "Only the app port (8080) may be open inbound."
  }
}

run "github_can_deploy_only_from_production_environment" {
  command = apply

  assert {
    condition     = alltrue([for s in local.github_subjects : endswith(s, ":environment:production")])
    error_message = "Only jobs in the GitHub 'production' environment may assume the deploy role."
  }
}

run "container_logs_are_retained" {
  command = apply

  assert {
    condition     = aws_cloudwatch_log_group.app.retention_in_days > 0
    error_message = "Container logs need a retention period."
  }
}
