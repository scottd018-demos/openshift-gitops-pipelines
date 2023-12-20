data "aws_subnet" "db_subnets" {
  count = length(var.db_subnet_ids)

  id = var.db_subnet_ids[count.index]
}

# NOTE: we use a random string so that this may be output for u
resource "random_string" "backend_password" {
  length           = 16
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
  min_upper        = 2
  override_special = "!#$%^&*"
}
