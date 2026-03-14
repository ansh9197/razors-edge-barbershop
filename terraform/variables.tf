# ============================================================
# terraform/variables.tf — All configurable variables
# ============================================================

variable "aws_region" {
  description = "AWS region (ap-south-1 = Mumbai — closest to Ludhiana)"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Project name prefix for all AWS resources"
  type        = string
  default     = "razors-edge"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "production"
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Must be development, staging, or production."
  }
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"   # 2 vCPU, 2GB RAM — good for a barbershop app
}

variable "public_key_path" {
  description = "Path to your SSH public key file"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "s3_bucket_name" {
  description = "S3 bucket name for storing booking data"
  type        = string
  default     = "razors-edge-bookings-prod"
}

variable "dynamo_table_name" {
  description = "DynamoDB table name for appointments"
  type        = string
  default     = "razors-edge-appointments"
}

variable "github_username" {
  description = "Your GitHub username"
  type        = string
  default     = "your-github-username"
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "razors-edge-barbershop"
}
