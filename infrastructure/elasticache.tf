locals {
  redis_type                = "redis"
  redis_version             = "6.x"
  redis_port                = 6379
  redis_subnet_ids          = [for subnet in data.aws_subnet.db_subnets : subnet.id]
  redis_instance_count      = 2
  redis_group_nane          = "yelb"
  redis_security_group_name = "${var.db_cluster_name}-redis"
}

resource "aws_security_group" "elasticache" {
  vpc_id      = local.db_vpc_id
  name        = local.redis_security_group_name
  description = "Security Group for Yelb Redis instance"

  ingress {
    description = "Ingress - Yelb Cache"
    from_port   = local.redis_port
    to_port     = local.redis_port
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
    Role      = "Yelb Cache"
  }
}

resource "aws_elasticache_subnet_group" "yelb" {
  name       = var.db_cluster_name
  subnet_ids = local.db_subnet_ids
}

resource "aws_elasticache_parameter_group" "yelb" {
  name   = var.db_cluster_name
  family = "redis6.x"

  parameter {
    name  = "cluster-enabled"
    value = "yes"
  }
}

resource "aws_elasticache_user" "yelb_default" {
  # we must have a default user, so we create it with zero permissions
  user_id       = "${var.db_cluster_name}-def"
  user_name     = "default"
  access_string = "on ~* -@all"
  engine        = "REDIS"
  passwords     = [random_string.backend_password.result]

  lifecycle {
    ignore_changes        = [passwords]
    create_before_destroy = true
  }
}

resource "aws_elasticache_user" "yelb" {
  user_id       = var.db_cluster_name
  user_name     = var.db_username
  access_string = "on ~* +@all"
  engine        = "REDIS"
  passwords     = [random_string.backend_password.result]

  lifecycle {
    ignore_changes        = [passwords]
    create_before_destroy = true
  }
}

resource "aws_elasticache_user_group" "yelb" {
  engine = "REDIS"

  user_group_id = local.redis_group_nane
  user_ids      = [aws_elasticache_user.yelb.user_id, aws_elasticache_user.yelb_default.user_id]
}

resource "aws_elasticache_replication_group" "yelb" {
  replication_group_id = substr("${var.db_cluster_name}", 0, 39)
  description          = "Redis for Yelb"

  engine         = "redis"
  engine_version = local.redis_version

  node_type                  = var.cache_instance_size
  port                       = 6379
  automatic_failover_enabled = true
  multi_az_enabled           = true
  parameter_group_name       = aws_elasticache_parameter_group.yelb.name

  # cluster size
  num_node_groups         = local.redis_instance_count
  replicas_per_node_group = 1

  # network
  subnet_group_name  = aws_elasticache_subnet_group.yelb.name
  security_group_ids = [aws_security_group.elasticache.id]

  # encryption/auth
  at_rest_encryption_enabled = false
  transit_encryption_enabled = true
  user_group_ids             = [aws_elasticache_user_group.yelb.id]

  lifecycle {
    create_before_destroy = true
  }
}
