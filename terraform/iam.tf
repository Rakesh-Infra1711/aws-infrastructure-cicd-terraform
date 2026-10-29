# Instance role for the application EC2 instances.
# No SSH keys: administrators connect through SSM Session Manager.

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "${local.name}-app-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "app_ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "app" {
  # Read ONLY the RDS-managed database secret
  statement {
    sid       = "ReadDbSecret"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [aws_db_instance.this.master_user_secret[0].secret_arn]
  }

  # Download application code at boot
  statement {
    sid       = "ReadAppCode"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.app.arn}/app/*"]
  }

  statement {
    sid       = "ListAppPrefixes"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.app.arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["app/*", "uploads/*"]
    }
  }

  # Application storage (user uploads) - its own prefix only
  statement {
    sid       = "AppStorage"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.app.arn}/uploads/*"]
  }
}

resource "aws_iam_role_policy" "app" {
  name   = "app-least-privilege"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app.json
}

resource "aws_iam_instance_profile" "app" {
  name = "${local.name}-app-profile"
  role = aws_iam_role.app.name
}
