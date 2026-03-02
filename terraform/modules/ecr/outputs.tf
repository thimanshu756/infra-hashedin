output "repository_urls" {
  description = "Map of service name to ECR repository URL"
  value       = { for name, repo in aws_ecr_repository.services : name => repo.repository_url }
}

output "registry_url" {
  description = "ECR registry URL (without repository name)"
  value       = split("/", values(aws_ecr_repository.services)[0].repository_url)[0]
}
