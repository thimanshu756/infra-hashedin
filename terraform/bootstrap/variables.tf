variable "aws_region" {
  description = "AWS region for the state backend"
  type        = string
  default     = "us-west-1"
}

variable "aws_account_id" {
  description = "AWS account ID (used to make bucket name globally unique)"
  type        = string
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "eks-assignment"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "Owner of the resources"
  type        = string
}
