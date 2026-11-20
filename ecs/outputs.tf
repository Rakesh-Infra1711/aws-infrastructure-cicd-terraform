output "ecr_repository_url" {
  description = "Where the pipeline pushes images"
  value       = aws_ecr_repository.app.repository_url
}

output "github_variables" {
  description = "Add these as repository variables in GitHub (Settings > Secrets and variables > Actions > Variables)"
  value = {
    ECS_DEPLOY_ROLE_ARN = aws_iam_role.github_deploy.arn
    ECR_REPOSITORY      = aws_ecr_repository.app.name
    ECS_CLUSTER         = aws_ecs_cluster.main.name
    ECS_SERVICE         = aws_ecs_service.app.name
    ECS_TASK_FAMILY     = aws_ecs_task_definition.app.family
  }
}

output "logs" {
  description = "Container logs"
  value       = "aws logs tail ${aws_cloudwatch_log_group.app.name} --follow --region ${var.aws_region}"
}
