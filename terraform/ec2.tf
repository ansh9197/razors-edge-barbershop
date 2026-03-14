# ============================================================
# terraform/ec2.tf — EC2 Instance for Razor's Edge App
# ============================================================

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket  = "razors-edge-tf-state"
    key     = "barbershop/terraform.tfstate"
    region  = "ap-south-1"
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = "razors-edge"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# ── Security Group ─────────────────────────────────────────
resource "aws_security_group" "app_sg" {
  name        = "${var.project_name}-sg"
  description = "Allow HTTP, HTTPS, SSH, app and monitoring ports"
  vpc_id      = aws_default_vpc.default.id

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access"
  }
  # App
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Node.js App"
  }
  # HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP"
  }
  # HTTPS
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS"
  }
  # Prometheus
  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Prometheus"
  }
  # Grafana
  ingress {
    from_port   = 3001
    to_port     = 3001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Grafana"
  }
  # Node exporter
  ingress {
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Node Exporter"
  }
  # All outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-security-group" }
}

# Use default VPC
resource "aws_default_vpc" "default" {
  tags = { Name = "Default VPC" }
}

# ── Key Pair ───────────────────────────────────────────────
resource "aws_key_pair" "app_key" {
  key_name   = "${var.project_name}-key"
  public_key = file(var.public_key_path)
}

# ── IAM Role for EC2 ──────────────────────────────────────
resource "aws_iam_role" "ec2_role" {
  name = "${var.project_name}-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "ec2_policy" {
  name = "${var.project_name}-ec2-policy"
  role = aws_iam_role.ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject","s3:GetObject","s3:ListBucket","s3:DeleteObject"]
        Resource = [
          "arn:aws:s3:::${var.s3_bucket_name}",
          "arn:aws:s3:::${var.s3_bucket_name}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem","dynamodb:GetItem","dynamodb:Scan","dynamodb:Query","dynamodb:UpdateItem"]
        Resource = "arn:aws:dynamodb:${var.aws_region}:*:table/${var.dynamo_table_name}"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-instance-profile"
  role = aws_iam_role.ec2_role.name
}

# ── EC2 Instance ──────────────────────────────────────────
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical (Ubuntu)
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-22.04-amd64-server-*"]
  }
}

resource "aws_instance" "app_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.app_key.key_name
  vpc_security_group_ids = [aws_security_group.app_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  # Bootstrap script — installs Docker, Docker Compose, clones repo
  user_data = <<-EOF
    #!/bin/bash
    set -e
    apt-get update -y
    apt-get install -y docker.io docker-compose git curl wget

    systemctl start docker
    systemctl enable docker
    usermod -aG docker ubuntu

    # Install Docker Compose v2
    curl -SL "https://github.com/docker/compose/releases/download/v2.23.0/docker-compose-linux-x86_64" \
      -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose

    # Clone and start the application
    cd /home/ubuntu
    git clone https://github.com/${var.github_username}/${var.github_repo}.git app
    cd app
    docker-compose up -d --build

    echo "✅ Razor's Edge deployed successfully!" > /home/ubuntu/deploy.log
  EOF

  tags = { Name = "${var.project_name}-server" }
}

# ── Elastic IP (Fixed Public IP) ─────────────────────────
resource "aws_eip" "app_eip" {
  instance = aws_instance.app_server.id
  domain   = "vpc"
  tags     = { Name = "${var.project_name}-eip" }
}

# ── Outputs ──────────────────────────────────────────────
output "ec2_public_ip" {
  value       = aws_eip.app_eip.public_ip
  description = "Public IP of the EC2 instance"
}

output "app_url" {
  value       = "http://${aws_eip.app_eip.public_ip}:3000"
  description = "Booking app URL"
}

output "grafana_url" {
  value       = "http://${aws_eip.app_eip.public_ip}:3001"
  description = "Grafana dashboard URL"
}

output "prometheus_url" {
  value       = "http://${aws_eip.app_eip.public_ip}:9090"
  description = "Prometheus URL"
}
