# =============================================================================
# Remote Backend Configuration
# =============================================================================
# Points to the S3 bucket and DynamoDB table created by bootstrap/.
# The bucket name includes the account ID, so update it when migrating accounts.
# =============================================================================

terraform {
  backend "s3" {
    bucket         = "eks-assignment-dev-tfstate-YOUR_AWS_ACCOUNT_ID"
    key            = "environments/dev/terraform.tfstate"
    region         = "us-west-1"
    dynamodb_table = "eks-assignment-dev-tflock"
    encrypt        = true
  }
}
