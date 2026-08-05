################################################################################
# Data Sources
################################################################################

# Endpoint and CA for the existing cluster the add-ons are installed onto.
data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

data "aws_partition" "current" {}
