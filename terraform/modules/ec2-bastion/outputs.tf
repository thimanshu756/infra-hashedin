output "instance_id" {
  description = "ID of the bastion EC2 instance"
  value       = aws_instance.bastion.id
}

output "instance_private_ip" {
  description = "Private IP address of the bastion"
  value       = aws_instance.bastion.private_ip
}

output "security_group_id" {
  description = "Security group ID of the bastion"
  value       = aws_security_group.bastion.id
}

output "iam_role_arn" {
  description = "ARN of the bastion IAM role"
  value       = aws_iam_role.bastion.arn
}

output "ssm_command" {
  description = "AWS SSM command to connect to the bastion"
  value       = "aws ssm start-session --target ${aws_instance.bastion.id} --region ${var.aws_region}"
}
