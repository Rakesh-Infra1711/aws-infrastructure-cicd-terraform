# ===========================================================================
# Application storage bucket (app code + user uploads)
# ===========================================================================
resource "aws_s3_bucket" "app" {
  bucket        = "${local.name}-app-${local.account_id}"
  force_destroy = true # demo environment: allow terraform destroy to empty it
}

resource "aws_s3_bucket_ownership_controls" "app" {
  bucket = aws_s3_bucket.app.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "app" {
  bucket                  = aws_s3_bucket.app.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "app" {
  bucket = aws_s3_bucket.app.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "app" {
  bucket = aws_s3_bucket.app.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms" # AWS-managed key (aws/s3)
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "app" {
  bucket = aws_s3_bucket.app.id
  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_s3_bucket_policy" "app" {
  bucket = aws_s3_bucket.app.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.app.arn, "${aws_s3_bucket.app.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.app]
}

# Application code is uploaded by Terraform; instances download it at boot.
# A change to any app file changes app_version, which updates the launch
# template and triggers an ASG rolling instance refresh.
locals {
  app_files   = ["app.py", "requirements.txt"]
  app_version = substr(sha256(join("", [for f in local.app_files : filesha256("${path.module}/../app/${f}")])), 0, 12)
}

resource "aws_s3_object" "app_code" {
  for_each = toset(local.app_files)

  bucket = aws_s3_bucket.app.id
  key    = "app/${each.value}"
  source = "${path.module}/../app/${each.value}"
  etag   = filemd5("${path.module}/../app/${each.value}")

  depends_on = [aws_s3_bucket_server_side_encryption_configuration.app]
}

# ===========================================================================
# ALB access logs bucket
# ALB log delivery only supports SSE-S3 (AES256), not SSE-KMS.
# ===========================================================================
resource "aws_s3_bucket" "alb_logs" {
  bucket        = "${local.name}-alb-logs-${local.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_ownership_controls" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket                  = aws_s3_bucket.alb_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  rule {
    id     = "expire-logs"
    status = "Enabled"
    filter {}
    expiration {
      days = var.alb_log_retention_days
    }
  }
}

# Regional Elastic Load Balancing account that writes the logs
data "aws_elb_service_account" "this" {}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowAlbLogDelivery"
        Effect    = "Allow"
        Principal = { AWS = data.aws_elb_service_account.this.arn }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.alb_logs.arn}/alb/AWSLogs/${local.account_id}/*"
      },
      {
        Sid       = "AllowAlbLogDeliveryService"
        Effect    = "Allow"
        Principal = { Service = "logdelivery.elasticloadbalancing.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.alb_logs.arn}/alb/AWSLogs/${local.account_id}/*"
      }
    ]
  })
  depends_on = [aws_s3_bucket_public_access_block.alb_logs]
}
