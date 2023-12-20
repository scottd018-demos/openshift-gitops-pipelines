variable "db_subnet_ids" {
  type = list(string)
}

module "infrastructure" {
  source = "../"

  db_subnet_ids = var.db_subnet_ids
}

output "infrastructure" {
  value = module.infrastructure
}
