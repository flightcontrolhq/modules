################################################################################
# Karpenter
################################################################################

output "karpenter_namespace" {
  description = "Kubernetes namespace where the Karpenter controller is installed."
  value       = helm_release.karpenter.namespace
}

output "karpenter_chart_version" {
  description = "Installed version of the Karpenter Helm chart."
  value       = helm_release.karpenter.version
}

output "karpenter_default_node_pool_release" {
  description = "Helm release name of the default NodePool chart (null if disabled)."
  value       = var.karpenter_default_node_pool_enabled ? helm_release.karpenter_default_node_pool[0].name : null
}
