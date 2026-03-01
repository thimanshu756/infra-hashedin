# OIDC GitHub Actions Module

## What it creates
- **OIDC Identity Provider** for GitHub Actions (`token.actions.githubusercontent.com`)
- **IAM Role** (`github-actions-role`) with trust policy restricted to specific repo + branch
- **Policy Attachments** — EKS, EC2, IAM, S3, DynamoDB full access

## Trust Policy
The role can only be assumed by GitHub Actions running from:
- Repository: `<github_org>/<github_repo>`
- Branch: `<github_branch>` (default: `IAC-DAY1`)

## Required inputs
| Variable | Description |
|---|---|
| `project_name` | Project name |
| `environment` | Environment |
| `owner` | Resource owner |
| `github_org` | GitHub organization or username |
| `github_repo` | GitHub repository name |

## Optional inputs
| Variable | Default | Description |
|---|---|---|
| `github_branch` | `IAC-DAY1` | Allowed branch |

## Outputs
| Output | Description |
|---|---|
| `oidc_provider_arn` | GitHub OIDC provider ARN |
| `github_actions_role_arn` | IAM role ARN for GitHub Actions |
| `github_actions_role_name` | IAM role name |

## GitHub Secrets Required
Set these in your repository settings:
- `AWS_ROLE_ARN` — the `github_actions_role_arn` output
- `AWS_ACCOUNT_ID` — your AWS account ID
- `TF_VAR_github_org` — your GitHub org
- `TF_VAR_github_repo` — your repo name
- `TF_VAR_owner` — resource owner name
