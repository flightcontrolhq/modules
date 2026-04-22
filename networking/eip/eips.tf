################################################################################
# Elastic IPs
################################################################################

resource "aws_eip" "this" {
  count = var.eip_count

  region               = var.region
  domain               = "vpc"
  network_border_group = var.network_border_group

  tags = merge(local.tags, {
    Name = format("%s-%02d", var.name, count.index + 1)
  })
}
