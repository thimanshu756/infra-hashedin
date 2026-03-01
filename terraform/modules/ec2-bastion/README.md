# EC2 Bastion Module

## What it creates
- **EC2 Instance** — Amazon Linux 2023 (t2.micro) in a private subnet
- **IAM Role + Instance Profile** with SSM access (no SSH keys needed)
- **Security Group** — egress only, no inbound from internet
- **User Data** — installs kubectl, helm, awscli v2, git; configures kubeconfig

## Access
Connect via AWS Systems Manager Session Manager:
```bash
aws ssm start-session --target <instance-id> --region <region>
```

## Required inputs
| Variable | Description |
|---|---|
| `project_name` | Project name |
| `environment` | Environment |
| `owner` | Resource owner |
| `vpc_id` | VPC ID |
| `subnet_id` | Private subnet ID |
| `eks_cluster_name` | EKS cluster name (for kubeconfig) |
| `aws_region` | AWS region (for kubeconfig) |

## Outputs
| Output | Description |
|---|---|
| `instance_id` | EC2 instance ID |
| `instance_private_ip` | Private IP address |
| `security_group_id` | Bastion SG ID |
| `iam_role_arn` | Bastion IAM role ARN |
| `ssm_command` | Ready-to-use SSM connect command |
