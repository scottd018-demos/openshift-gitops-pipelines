output "postgres_endpoint" {
  value = aws_rds_cluster.yelb.endpoint
}

output "redis_endpoint" {
  value = aws_elasticache_replication_group.yelb.configuration_endpoint_address
}

output "backend_password" {
  value = random_string.backend_password.result
}
