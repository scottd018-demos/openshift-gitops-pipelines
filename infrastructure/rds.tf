locals {
  db_type                    = "aurora-postgresql"
  db_parameter_group         = "aurora-postgresql15"
  db_version                 = "15.4"
  db_port                    = 5432
  db_vpc_id                  = data.aws_subnet.db_subnets[0].vpc_id
  db_subnet_ids              = [for subnet in data.aws_subnet.db_subnets : subnet.id]
  db_subnet_cidrs            = [for subnet in data.aws_subnet.db_subnets : subnet.cidr_block]
  db_instance_count          = 1
  db_security_group_name     = "${var.db_cluster_name}-database"
  auto_minor_version_upgrade = true
}

resource "aws_security_group" "rds" {
  vpc_id      = local.db_vpc_id
  name        = local.db_security_group_name
  description = "Security Group for Yelb PostgreSQL instance"

  ingress {
    description = "Ingress - Yelb DB"
    from_port   = local.db_port
    to_port     = local.db_port
    protocol    = "tcp"
    cidr_blocks = local.db_subnet_cidrs
  }

  egress {
    description = "Internet"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = var.db_cluster_name
    Terraform = "true"
    Role      = "Yelb Database"
  }
}

resource "aws_db_subnet_group" "yelb" {
  name       = var.db_cluster_name
  subnet_ids = local.db_subnet_ids
}

locals {
  db_parameters = [
    {
      name  = "idle_in_transaction_session_timeout"
      value = 60000
    },
    {
      name  = "tcp_keepalives_count"
      value = 10
    },
    {
      name  = "tcp_keepalives_idle"
      value = 60
    },
    {
      name  = "tcp_keepalives_interval"
      value = 60
    },
    {
      name  = "statement_timeout"
      value = 600
    }
  ]
}

resource "aws_rds_cluster_parameter_group" "yelb" {
  name        = var.db_cluster_name
  family      = local.db_parameter_group
  description = "Yelb default cluster parameter group."

  dynamic "parameter" {
    for_each = toset(local.db_parameters)

    content {
      name  = parameter.value.name
      value = parameter.value.value

      # we need to use the 'pending-reboot' apply method to avoid automation failure when
      # certain db parameters are modified, which will cause a failure.  In addition, this
      # can be seen as a safety measure to ensure production instances do not get rebooted
      # each time automation is run
      apply_method = "pending-reboot"
    }
  }
}

resource "aws_db_parameter_group" "yelb" {
  name        = var.db_cluster_name
  family      = local.db_parameter_group
  description = "Yelb default database parameter group."
}

resource "aws_rds_cluster" "yelb" {
  # postgres
  engine                          = local.db_type
  engine_version                  = local.db_version
  cluster_identifier              = var.db_cluster_name
  database_name                   = var.db_cluster_name
  master_username                 = var.db_username
  master_password                 = random_string.backend_password.result
  port                            = local.db_port
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.yelb.name
  skip_final_snapshot             = true

  # storage
  storage_encrypted = false

  # network
  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.yelb.name

  lifecycle {
    ignore_changes = [master_password]
  }
}

resource "aws_rds_cluster_instance" "yelb" {
  count = local.db_instance_count

  identifier                 = "${var.db_cluster_name}-db-${count.index}"
  cluster_identifier         = aws_rds_cluster.yelb.id
  instance_class             = var.db_instance_size
  engine                     = aws_rds_cluster.yelb.engine
  engine_version             = aws_rds_cluster.yelb.engine_version
  db_parameter_group_name    = aws_db_parameter_group.yelb.name
  auto_minor_version_upgrade = local.auto_minor_version_upgrade
}
