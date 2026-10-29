resource "aws_db_subnet_group" "this" {
  name       = "${local.name}-db-subnets"
  subnet_ids = aws_subnet.db[*].id
  tags       = { Name = "${local.name}-db-subnets" }
}

# Enforce TLS for every client connection (encryption in transit)
resource "aws_db_parameter_group" "this" {
  name   = "${local.name}-mysql84"
  family = "mysql8.4"

  parameter {
    name  = "require_secure_transport"
    value = "1"
  }
}

resource "aws_db_instance" "this" {
  identifier     = "${local.name}-mysql"
  engine         = "mysql"
  engine_version = "8.4"
  instance_class = var.db_instance_class

  db_name  = var.db_name
  username = var.db_username
  # RDS generates the master password and stores/rotates it in
  # AWS Secrets Manager - it never appears in Terraform code or state.
  manage_master_user_password = true

  allocated_storage     = 20
  max_allocated_storage = 50
  storage_type          = "gp3"
  storage_encrypted     = true # encryption at rest (AWS-managed KMS key)

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = false
  multi_az               = var.db_multi_az

  backup_retention_period         = 7
  backup_window                   = "19:00-20:00" # UTC = 00:30-01:30 IST
  maintenance_window              = "sun:20:30-sun:21:30"
  copy_tags_to_snapshot           = true
  auto_minor_version_upgrade      = true
  enabled_cloudwatch_logs_exports = ["error", "slowquery"]

  deletion_protection       = var.db_deletion_protection
  skip_final_snapshot       = !var.db_deletion_protection
  final_snapshot_identifier = var.db_deletion_protection ? "${local.name}-mysql-final" : null
  apply_immediately         = true

  tags = { Name = "${local.name}-mysql" }
}
