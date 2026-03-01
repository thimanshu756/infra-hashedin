# =============================================================================
# EC2 Bastion Module
# =============================================================================
# Creates: EC2 bastion host in private subnet with SSM access, kubectl, helm
# Access via: aws ssm start-session --target <instance-id>
# =============================================================================

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Owner       = var.owner
    ManagedBy   = "terraform"
  }
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# -----------------------------------------------------------------------------
# IAM Role for SSM Access
# -----------------------------------------------------------------------------
resource "aws_iam_role" "bastion" {
  name = "${var.project_name}-${var.environment}-bastion-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-bastion-role"
  })
}

resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.bastion.name
}

# Allow bastion to describe EKS clusters (needed for kubeconfig)
resource "aws_iam_role_policy" "bastion_eks" {
  name = "${var.project_name}-${var.environment}-bastion-eks-policy"
  role = aws_iam_role.bastion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${var.project_name}-${var.environment}-bastion-profile"
  role = aws_iam_role.bastion.name

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-bastion-profile"
  })
}

# -----------------------------------------------------------------------------
# Security Group — Egress Only (no inbound from internet)
# -----------------------------------------------------------------------------
resource "aws_security_group" "bastion" {
  name_prefix = "${var.project_name}-${var.environment}-bastion-sg-"
  description = "Bastion security group - egress only, no inbound from internet"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-bastion-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# EC2 Instance
# -----------------------------------------------------------------------------
resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  iam_instance_profile   = aws_iam_instance_profile.bastion.name
  vpc_security_group_ids = [aws_security_group.bastion.id]

  root_block_device {
    volume_size = 30
    volume_type = "gp2"
    encrypted   = true
  }

  user_data = base64encode(templatefile("${path.module}/userdata.sh", {
    cluster_name = var.eks_cluster_name
    aws_region   = var.aws_region
  }))

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2 enforced
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-bastion"
  })
}
