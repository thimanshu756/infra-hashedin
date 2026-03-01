# Bootstrap Module

## What it creates
- **S3 Bucket** — Stores Terraform remote state with versioning and AES256 encryption
- **DynamoDB Table** — State locking with PAY_PER_REQUEST billing (hash key: `LockID`)

Both resources have `prevent_destroy = true` lifecycle rules.

## Required inputs
| Variable | Description |
|---|---|
| `aws_account_id` | AWS account ID (makes bucket name globally unique) |
| `owner` | Resource owner for tagging |

## Outputs
| Output | Description |
|---|---|
| `state_bucket_name` | S3 bucket name for backend config |
| `state_bucket_arn` | S3 bucket ARN |
| `dynamodb_table_name` | DynamoDB table name for backend config |
| `dynamodb_table_arn` | DynamoDB table ARN |

## Usage
```bash
cd terraform/bootstrap
terraform init
terraform plan -var="aws_account_id=123456789012" -var="owner=your-name"
terraform apply -var="aws_account_id=123456789012" -var="owner=your-name"
```

**Important:** This uses local state. Apply this FIRST before any other module.
