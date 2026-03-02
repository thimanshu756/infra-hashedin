# VPC Module

## What it creates
- **VPC** with DNS support and hostnames enabled
- **1 Public Subnet** with auto-assign public IP (AZ-a)
- **2 Private Subnets** across two AZs (for EKS high availability)
- **Internet Gateway** attached to VPC
- **NAT Gateway** in public subnet (single NAT — cost optimized for dev)
- **Elastic IP** for NAT Gateway
- **Route Tables** — public → IGW, private → NAT
- **VPC Flow Logs** to CloudWatch Logs (30-day retention)

Subnets are tagged for Kubernetes ELB discovery (`kubernetes.io/role/elb` and `kubernetes.io/role/internal-elb`).

## Required inputs
| Variable | Description |
|---|---|
| `project_name` | Project name for naming |
| `environment` | Environment (dev/staging/prod) |
| `owner` | Resource owner |

## Optional inputs
| Variable | Default | Description |
|---|---|---|
| `vpc_cidr` | `10.0.0.0/16` | VPC CIDR block |
| `public_subnet_cidr` | `10.0.1.0/24` | Public subnet CIDR |
| `private_subnet_cidrs` | `["10.0.2.0/24", "10.0.3.0/24"]` | Private subnet CIDRs |
| `availability_zones` | `["us-west-1a", "us-west-1b"]` | AZs for subnets |

## Outputs
| Output | Description |
|---|---|
| `vpc_id` | VPC ID |
| `vpc_cidr_block` | VPC CIDR block |
| `public_subnet_id` | Public subnet ID |
| `private_subnet_ids` | List of private subnet IDs |
| `nat_gateway_id` | NAT Gateway ID |
| `internet_gateway_id` | Internet Gateway ID |
