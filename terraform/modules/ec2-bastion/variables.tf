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

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "subnet_id" {
  description = "ID of the private subnet for the bastion host"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the bastion"
  type        = string
  default     = "t3.micro"
}

variable "eks_cluster_name" {
  description = "Name of the EKS cluster (for kubeconfig)"
  type        = string
}

variable "aws_region" {
  description = "AWS region (for kubeconfig)"
  type        = string
}
