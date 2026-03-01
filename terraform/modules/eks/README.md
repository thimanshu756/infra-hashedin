# EKS Module

## What it creates
- **EKS Cluster** with private-only API endpoint (`prevent_destroy = true`)
- **Managed Node Group** — 2-3 t2.medium nodes in private subnets (20GB gp2)
- **Cluster IAM Role** with `AmazonEKSClusterPolicy`
- **Node IAM Role** with `AmazonEKSWorkerNodePolicy`, `AmazonEC2ContainerRegistryReadOnly`, `AmazonEKS_CNI_Policy`
- **Security Groups** — cluster SG and node SG with proper communication rules
- **OIDC Provider** for IRSA (IAM Roles for Service Accounts)
- **Cluster Add-ons** — vpc-cni, coredns, kube-proxy
- **aws-auth ConfigMap** — maps node role to `system:nodes` group

## Required inputs
| Variable | Description |
|---|---|
| `project_name` | Project name |
| `environment` | Environment |
| `owner` | Resource owner |
| `cluster_name` | EKS cluster name |
| `vpc_id` | VPC ID |
| `private_subnet_ids` | Private subnet IDs for cluster and nodes |

## Optional inputs
| Variable | Default | Description |
|---|---|---|
| `kubernetes_version` | `1.29` | Kubernetes version |
| `node_instance_type` | `t2.medium` | Node instance type |
| `node_desired_count` | `2` | Desired node count |
| `node_min_count` | `2` | Minimum nodes |
| `node_max_count` | `3` | Maximum nodes |

## Outputs
| Output | Description |
|---|---|
| `cluster_name` | EKS cluster name |
| `cluster_endpoint` | Cluster API endpoint |
| `cluster_arn` | Cluster ARN |
| `cluster_certificate_authority_data` | Base64 CA data |
| `cluster_security_group_id` | Cluster SG ID |
| `node_security_group_id` | Node SG ID |
| `node_role_arn` | Node IAM role ARN |
| `oidc_provider_arn` | OIDC provider ARN (for IRSA) |
| `oidc_provider_url` | OIDC provider URL |

## Important
The cluster endpoint is **private only**. kubectl commands must be run from inside the VPC (e.g., bastion host via SSM).
