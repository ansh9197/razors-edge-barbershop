# ============================================================
# terraform/s3.tf — S3 Bucket for Booking Data Storage
# ============================================================

# ── Main Bookings Bucket ──────────────────────────────────
resource "aws_s3_bucket" "bookings" {
  bucket        = var.s3_bucket_name
  force_destroy = false
  tags          = { Name = "${var.project_name}-bookings" }
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "bookings" {
  bucket                  = aws_s3_bucket.bookings.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning (recover deleted bookings)
resource "aws_s3_bucket_versioning" "bookings" {
  bucket = aws_s3_bucket.bookings.id
  versioning_configuration { status = "Enabled" }
}

# Server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "bookings" {
  bucket = aws_s3_bucket.bookings.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Lifecycle — move old bookings to cheaper storage
resource "aws_s3_bucket_lifecycle_configuration" "bookings" {
  bucket = aws_s3_bucket.bookings.id
  rule {
    id     = "archive-bookings"
    status = "Enabled"
    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }
    transition {
      days          = 365
      storage_class = "GLACIER"
    }
  }
}

# ── Terraform State Bucket ────────────────────────────────
resource "aws_s3_bucket" "tf_state" {
  bucket        = "${var.project_name}-tf-state"
  force_destroy = false
  tags          = { Name = "${var.project_name}-terraform-state" }
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ── Outputs ──────────────────────────────────────────────
output "s3_bucket_name" {
  value       = aws_s3_bucket.bookings.bucket
  description = "Name of the bookings S3 bucket"
}

output "s3_bucket_arn" {
  value       = aws_s3_bucket.bookings.arn
  description = "ARN of the bookings S3 bucket"
}
