################################################################################
# OIDC Identity Provider
#
# Created so consumer workloads can use IRSA (assume an IAM role from a
# Kubernetes service account JWT). Pod Identity is preferred for the helpers
# this module ships, but IRSA remains useful for app workloads where Pod
# Identity isn't supported by the upstream tooling.
################################################################################

resource "aws_iam_openid_connect_provider" "this" {
  url             = local.oidc_issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]

  tags = merge(local.tags, {
    Name = "${var.name}-oidc"
  })
}
