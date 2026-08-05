################################################################################
# Karpenter controller (Helm)
#
# CRDs are managed by the dedicated karpenter-crd chart because Helm does not
# upgrade CRDs bundled inside a chart's crds/ directory. Both charts are pinned
# to the same version. The AWS-side prerequisites come from module.karpenter
# in this same stack (see eks_karpenter.tf).
################################################################################

resource "helm_release" "karpenter_crd" {
  count = var.karpenter_enabled ? 1 : 0

  name       = "karpenter-crd"
  namespace  = var.karpenter_controller_namespace
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter-crd"
  version    = var.karpenter_chart_version

  create_namespace = true
}

resource "helm_release" "karpenter" {
  count = var.karpenter_enabled ? 1 : 0

  name       = "karpenter"
  namespace  = var.karpenter_controller_namespace
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.karpenter_chart_version

  skip_crds = true

  values = concat(
    [
      yamlencode({
        settings = {
          clusterName       = var.cluster_name
          interruptionQueue = module.karpenter[0].interruption_queue_name
        }
        # Must match the Pod Identity association created by module.karpenter.
        serviceAccount = {
          name = var.karpenter_controller_service_account
        }
      }),
    ],
    var.karpenter_helm_values,
  )

  # The controller pod needs the Pod Identity association and interruption
  # queue to exist before it starts.
  depends_on = [
    helm_release.karpenter_crd,
    module.karpenter,
  ]
}

################################################################################
# Default NodePool + EC2NodeClass
#
# Delivered as a local chart because the Helm provider is the only Kubernetes
# access this stack has. Nodes launch into the node subnets with the cluster
# security group and the Karpenter node instance profile.
################################################################################

resource "helm_release" "karpenter_default_node_pool" {
  count = var.karpenter_enabled && var.karpenter_default_node_pool_enabled ? 1 : 0

  name      = "karpenter-default-node-pool"
  namespace = var.karpenter_controller_namespace
  chart     = "${path.module}/charts/karpenter-resources"

  values = [
    yamlencode({
      ec2NodeClass = {
        name             = "default"
        instanceProfile  = module.karpenter[0].node_instance_profile_name
        subnetIds        = var.node_subnet_ids
        securityGroupIds = [var.cluster_security_group_id]
        tags             = local.tags
      }
      nodePool = {
        name               = "default"
        capacityTypes      = var.karpenter_default_node_pool.capacity_types
        instanceCategories = var.karpenter_default_node_pool.instance_categories
        architectures      = var.karpenter_default_node_pool.architectures
        cpuLimit           = var.karpenter_default_node_pool.cpu_limit
        expireAfter        = var.karpenter_default_node_pool.expire_after
      }
    }),
  ]

  depends_on = [helm_release.karpenter]
}
