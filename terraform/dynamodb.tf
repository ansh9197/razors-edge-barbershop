# ============================================================
# terraform/dynamodb.tf — DynamoDB Table for Appointments
# ============================================================

# ── Appointments Table ────────────────────────────────────
resource "aws_dynamodb_table" "appointments" {
  name         = var.dynamo_table_name
  billing_mode = "PAY_PER_REQUEST"  # No capacity planning needed
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "date"
    type = "S"
  }

  attribute {
    name = "phone"
    type = "S"
  }

  # Index to query by date (e.g. today's appointments)
  global_secondary_index {
    name            = "DateIndex"
    hash_key        = "date"
    projection_type = "ALL"
  }

  # Index to query by customer phone
  global_secondary_index {
    name            = "PhoneIndex"
    hash_key        = "phone"
    projection_type = "ALL"
  }

  # Automatic backups
  point_in_time_recovery {
    enabled = true
  }

  # Encryption at rest
  server_side_encryption {
    enabled = true
  }

  tags = {
    Name = "${var.project_name}-appointments"
  }
}

# ── State Lock Table (for Terraform backend) ──────────────
resource "aws_dynamodb_table" "tf_lock" {
  name         = "${var.project_name}-tf-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = { Name = "${var.project_name}-terraform-lock" }
}

# ── Outputs ──────────────────────────────────────────────
output "dynamodb_table_name" {
  value       = aws_dynamodb_table.appointments.name
  description = "DynamoDB appointments table name"
}

output "dynamodb_table_arn" {
  value       = aws_dynamodb_table.appointments.arn
  description = "DynamoDB appointments table ARN"
}
