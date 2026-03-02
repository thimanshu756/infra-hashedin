variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "owner" {
  description = "Owner of the resources"
  type        = string
}

variable "service_names" {
  description = "List of microservice names to create ECR repositories for"
  type        = list(string)
  default     = ["users-service", "products-service", "orders-service", "frontend"]
}
