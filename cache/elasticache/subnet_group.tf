################################################################################
# ElastiCache Subnet Group
################################################################################

resource "aws_elasticache_subnet_group" "this" {
  count = local.is_serverless ? 0 : 1

  name        = var.name
  description = "Subnet group for ${var.name} ElastiCache cluster"
  subnet_ids  = var.subnet_ids

  tags = merge(local.tags, {
    Name = var.name
  })
}
