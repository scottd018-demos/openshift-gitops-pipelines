variable "db_cluster_name" {
  type    = string
  default = "yelb"
}

variable "db_instance_size" {
  type    = string
  default = "db.t3.medium"
}

variable "db_username" {
  type      = string
  default   = "yelb"
  sensitive = true
}

variable "db_subnet_ids" {
  type = list(string)

  validation {
    condition     = length(var.db_subnet_ids) >= 2
    error_message = "The 'db_subnet_ids' variable must have a minimum length of 2 as RDS requires a minimum of 2 subnets in different AZs."
  }
}

variable "cache_instance_size" {
  type    = string
  default = "cache.t2.small"
}
