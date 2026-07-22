################################################################################
# Data Sources
################################################################################

# Endpoint and CA for the existing cluster the components are installed onto.
data "aws_eks_cluster" "this" {
  name = var.cluster_name
}
