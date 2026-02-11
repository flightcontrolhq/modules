################################################################################
# DB Subnet Group
################################################################################

resource "aws_db_subnet_group" "this" {
  count = local.create_subnet_group ? 1 : 0

  name        = var.name
  description = "Subnet group for ${var.name} Aurora cluster"
  subnet_ids  = var.subnet_ids

  tags = merge(local.tags, {
    Name = var.name
  })
}
