provider "aws" {
  region = var.region
}

# Authenticates against the existing cluster. Tokens are minted per apply via
# `aws eks get-token`, so no cluster credentials are stored in state. The
# runner needs the AWS CLI on PATH and network reachability to the cluster API
# endpoint — attach the cluster's Ravion Runner security group to the
# execution environment running this stack.
provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = concat(
        ["eks", "get-token", "--cluster-name", var.cluster_name],
        var.region == null ? [] : ["--region", var.region],
      )
    }
  }
}
