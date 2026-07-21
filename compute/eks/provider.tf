provider "aws" {
  region = var.region
}

# Authenticates against the cluster this stack creates. Tokens are minted per
# apply via `aws eks get-token`, so no cluster credentials are stored in state.
# The runner needs the AWS CLI on PATH and network reachability to the cluster
# API endpoint.
provider "helm" {
  kubernetes = {
    host                   = module.cluster.cluster_endpoint
    cluster_ca_certificate = base64decode(module.cluster.cluster_certificate_authority_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = concat(
        ["eks", "get-token", "--cluster-name", module.cluster.cluster_name],
        var.region == null ? [] : ["--region", var.region],
      )
    }
  }
}
