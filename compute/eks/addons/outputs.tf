################################################################################
# AWS Load Balancer Controller
################################################################################

output "lb_controller_chart_version" {
  description = "Installed version of the aws-load-balancer-controller Helm chart (null if disabled)."
  value       = local.lb_controller_install ? helm_release.lb_controller[0].version : null
}

output "lb_controller_namespace" {
  description = "Namespace where the AWS Load Balancer Controller is installed (null if disabled)."
  value       = local.lb_controller_install ? helm_release.lb_controller[0].namespace : null
}

################################################################################
# EBS CSI Driver
################################################################################

output "ebs_csi_addon_version" {
  description = "Resolved version of the aws-ebs-csi-driver EKS add-on (null if disabled)."
  value       = var.ebs_csi_driver_enabled ? aws_eks_addon.ebs_csi[0].addon_version : null
}

output "ebs_csi_role_arn" {
  description = "ARN of the EBS CSI driver Pod Identity role (null if disabled)."
  value       = var.ebs_csi_driver_enabled ? module.ebs_csi_role[0].role_arn : null
}

################################################################################
# CloudWatch Observability
################################################################################

output "cloudwatch_observability_addon_version" {
  description = "Resolved version of the amazon-cloudwatch-observability EKS add-on (null if disabled)."
  value       = var.cloudwatch_observability_enabled ? aws_eks_addon.cloudwatch_observability[0].addon_version : null
}

output "cloudwatch_observability_role_arn" {
  description = "ARN of the CloudWatch Observability add-on Pod Identity role (null if disabled)."
  value       = var.cloudwatch_observability_enabled ? module.cloudwatch_observability_role[0].role_arn : null
}

output "container_log_group" {
  description = "CloudWatch log group Fluent Bit ships container stdout/stderr to (null if the add-on is disabled). The dashboard's service log views read this group."
  value       = var.cloudwatch_observability_enabled ? "/aws/containerinsights/${var.cluster_name}/application" : null
}

output "log_stream_template" {
  description = "Shape of a log stream name in container_log_group (null if the add-on is disabled). Fluent Bit writes '<node>-<tail tag>', so the stream is node-first and a per-service reader matches the '_<namespace>_' / '_<container>-' substrings or the kubernetes.* fields inside each event — a stream *prefix* cannot scope to a workload."
  value       = var.cloudwatch_observability_enabled ? local.container_log_stream_template : null
}

output "dataplane_log_group" {
  description = "CloudWatch log group Fluent Bit ships kubelet, containerd, and CNI logs to (null if the add-on is disabled)."
  value       = var.cloudwatch_observability_enabled ? "/aws/containerinsights/${var.cluster_name}/dataplane" : null
}

################################################################################
# External Secrets Operator
################################################################################

output "eso_namespace" {
  description = "Kubernetes namespace where the External Secrets Operator is installed (null if disabled)."
  value       = var.eso_enabled ? helm_release.external_secrets[0].namespace : null
}

output "eso_chart_version" {
  description = "Installed version of the external-secrets Helm chart (null if disabled)."
  value       = var.eso_enabled ? helm_release.external_secrets[0].version : null
}

output "eso_role_arn" {
  description = "ARN of the External Secrets Operator Pod Identity role (null if disabled)."
  value       = var.eso_enabled ? module.external_secrets_role[0].role_arn : null
}

output "eso_secrets_manager_store_name" {
  description = "Name of the cluster-scoped AWS Secrets Manager store (kind ClusterSecretStore, apiVersion external-secrets.io/v1) that workload charts reference for Secrets Manager secrets (null if disabled)."
  value       = var.eso_enabled && var.eso_cluster_secret_stores_enabled ? var.eso_secrets_manager_store_name : null
}

output "eso_parameter_store_store_name" {
  description = "Name of the cluster-scoped AWS SSM Parameter Store store (kind ClusterSecretStore, apiVersion external-secrets.io/v1) that workload charts reference for SSM parameters (null if disabled)."
  value       = var.eso_enabled && var.eso_cluster_secret_stores_enabled ? var.eso_parameter_store_store_name : null
}

################################################################################
# Karpenter
################################################################################

output "karpenter_namespace" {
  description = "Kubernetes namespace where the Karpenter controller is installed (null if disabled)."
  value       = var.karpenter_enabled ? helm_release.karpenter[0].namespace : null
}

output "karpenter_chart_version" {
  description = "Installed version of the Karpenter Helm chart (null if disabled)."
  value       = var.karpenter_enabled ? helm_release.karpenter[0].version : null
}

output "karpenter_default_node_pool_release" {
  description = "Helm release name of the default NodePool chart (null if disabled)."
  value       = var.karpenter_enabled && var.karpenter_default_node_pool_enabled ? helm_release.karpenter_default_node_pool[0].name : null
}

output "karpenter_controller_role_arn" {
  description = "ARN of the Karpenter controller IAM role (null if disabled)."
  value       = var.karpenter_enabled ? module.karpenter[0].controller_role_arn : null
}

output "karpenter_node_role_arn" {
  description = "ARN of the IAM role attached to Karpenter-launched nodes (null if disabled)."
  value       = var.karpenter_enabled ? module.karpenter[0].node_role_arn : null
}

output "karpenter_node_instance_profile_name" {
  description = "Instance profile name used by the default EC2NodeClass (null if disabled)."
  value       = var.karpenter_enabled ? module.karpenter[0].node_instance_profile_name : null
}

output "karpenter_interruption_queue_name" {
  description = "Name of the SQS interruption queue (null if disabled)."
  value       = var.karpenter_enabled ? module.karpenter[0].interruption_queue_name : null
}

################################################################################
# Shared Load Balancers
################################################################################

output "public_alb_arn" {
  description = "ARN of the shared public ALB (null if disabled)."
  value       = var.public_alb_enabled ? module.public_alb[0].alb_arn : null
}

output "public_alb_dns_name" {
  description = "DNS name of the shared public ALB (null if disabled)."
  value       = var.public_alb_enabled ? module.public_alb[0].alb_dns_name : null
}

output "public_alb_zone_id" {
  description = "Route 53 zone ID of the shared public ALB (null if disabled)."
  value       = var.public_alb_enabled ? module.public_alb[0].alb_zone_id : null
}

output "public_alb_arn_suffix" {
  description = "ARN suffix of the shared public ALB, for CloudWatch metrics (null if disabled)."
  value       = var.public_alb_enabled ? module.public_alb[0].alb_arn_suffix : null
}

output "public_alb_security_group_id" {
  description = "Security group ID of the shared public ALB (null if disabled)."
  value       = var.public_alb_enabled ? module.public_alb[0].security_group_id : null
}

output "public_alb_http_listener_arn" {
  description = "ARN of the shared public ALB HTTP listener (null if disabled)."
  value       = var.public_alb_enabled ? module.public_alb[0].http_listener_arn : null
}

output "public_alb_https_listener_arn" {
  description = "ARN of the shared public ALB HTTPS listener (null if disabled)."
  value       = var.public_alb_enabled ? module.public_alb[0].https_listener_arn : null
}

output "private_alb_arn" {
  description = "ARN of the shared private ALB (null if disabled)."
  value       = var.private_alb_enabled ? module.private_alb[0].alb_arn : null
}

output "private_alb_dns_name" {
  description = "DNS name of the shared private ALB (null if disabled)."
  value       = var.private_alb_enabled ? module.private_alb[0].alb_dns_name : null
}

output "private_alb_zone_id" {
  description = "Route 53 zone ID of the shared private ALB (null if disabled)."
  value       = var.private_alb_enabled ? module.private_alb[0].alb_zone_id : null
}

output "private_alb_arn_suffix" {
  description = "ARN suffix of the shared private ALB, for CloudWatch metrics (null if disabled)."
  value       = var.private_alb_enabled ? module.private_alb[0].alb_arn_suffix : null
}

output "private_alb_security_group_id" {
  description = "Security group ID of the shared private ALB (null if disabled)."
  value       = var.private_alb_enabled ? module.private_alb[0].security_group_id : null
}

output "private_alb_http_listener_arn" {
  description = "ARN of the shared private ALB HTTP listener (null if disabled)."
  value       = var.private_alb_enabled ? module.private_alb[0].http_listener_arn : null
}

output "private_alb_https_listener_arn" {
  description = "ARN of the shared private ALB HTTPS listener (null if disabled)."
  value       = var.private_alb_enabled ? module.private_alb[0].https_listener_arn : null
}

output "public_nlb_arn" {
  description = "ARN of the shared public NLB (null if disabled)."
  value       = var.public_nlb_enabled ? module.public_nlb[0].nlb_arn : null
}

output "public_nlb_dns_name" {
  description = "DNS name of the shared public NLB (null if disabled)."
  value       = var.public_nlb_enabled ? module.public_nlb[0].nlb_dns_name : null
}

output "public_nlb_zone_id" {
  description = "Route 53 zone ID of the shared public NLB (null if disabled)."
  value       = var.public_nlb_enabled ? module.public_nlb[0].nlb_zone_id : null
}

output "public_nlb_arn_suffix" {
  description = "ARN suffix of the shared public NLB, for CloudWatch metrics (null if disabled)."
  value       = var.public_nlb_enabled ? module.public_nlb[0].nlb_arn_suffix : null
}

output "public_nlb_security_group_id" {
  description = "Security group ID of the shared public NLB (null if disabled)."
  value       = var.public_nlb_enabled ? module.public_nlb[0].security_group_id : null
}

output "private_nlb_arn" {
  description = "ARN of the shared private NLB (null if disabled)."
  value       = var.private_nlb_enabled ? module.private_nlb[0].nlb_arn : null
}

output "private_nlb_dns_name" {
  description = "DNS name of the shared private NLB (null if disabled)."
  value       = var.private_nlb_enabled ? module.private_nlb[0].nlb_dns_name : null
}

output "private_nlb_zone_id" {
  description = "Route 53 zone ID of the shared private NLB (null if disabled)."
  value       = var.private_nlb_enabled ? module.private_nlb[0].nlb_zone_id : null
}

output "private_nlb_arn_suffix" {
  description = "ARN suffix of the shared private NLB, for CloudWatch metrics (null if disabled)."
  value       = var.private_nlb_enabled ? module.private_nlb[0].nlb_arn_suffix : null
}

output "private_nlb_security_group_id" {
  description = "Security group ID of the shared private NLB (null if disabled)."
  value       = var.private_nlb_enabled ? module.private_nlb[0].security_group_id : null
}

################################################################################
# Ravion Beacon
################################################################################

output "beacon_namespace" {
  description = "Kubernetes namespace where the Beacon agent is installed (null if disabled)."
  value       = var.beacon_enabled ? helm_release.beacon[0].namespace : null
}

output "beacon_chart_version" {
  description = "Installed version of the Beacon Helm chart (null if disabled). This is the chart version, not the running agent version — the control plane owns that."
  value       = var.beacon_enabled ? helm_release.beacon[0].version : null
}

output "beacon_agent_id" {
  description = "Ravion Beacon agent record id (bagt_...) for this cluster (null if disabled). Stable across rotations — correlate agent logs by it."
  # A computed attribute of the credential resource, not secret material: the
  # client secret is the only sensitive attribute and is never output.
  value = var.beacon_enabled ? ravion_beacon_credential.this[0].beacon_agent_id : null
}

output "beacon_client_id" {
  description = "WorkOS M2M client id the agent authenticates as (null if disabled). Not a secret, and identical for every cluster in the organization — the shared application's client id."
  value       = var.beacon_enabled ? ravion_beacon_credential.this[0].client_id : null
}

output "beacon_client_secret_id" {
  description = "WorkOS id of the secret issued to this cluster (null if disabled). Not the secret itself: it identifies which credential a connecting agent is presenting."
  value       = var.beacon_enabled ? ravion_beacon_credential.this[0].secret_id : null
}

output "beacon_credential_secret_arn" {
  description = "ARN of the AWS Secrets Manager secret mirroring the agent's credential (null if disabled). An operator recovery copy of what Terraform state holds — nothing reads it back."
  value       = var.beacon_enabled ? aws_secretsmanager_secret.beacon_credential[0].arn : null
}

################################################################################
# Workload metrics (Amazon Managed Prometheus)
################################################################################

output "amp_workspace_id" {
  description = "Amazon Managed Prometheus workspace the collector writes to (null if metrics are disabled). The created workspace, or the one passed as amp_workspace_id."
  value       = local.amp_workspace_id
}

output "amp_workspace_arn" {
  description = "ARN of the AMP workspace (null if metrics are disabled). What a query role or cross-account grant is scoped to."
  value       = local.amp_workspace_arn
}

output "amp_remote_write_endpoint" {
  description = "SigV4-signed remote-write URL the collector posts to (null if metrics are disabled)."
  value       = local.amp_remote_write_endpoint
}

output "amp_query_endpoint" {
  description = "Prometheus-compatible query base URL for the workspace (null if metrics are disabled). Use it as-is as a Grafana datasource URL; append /api/v1/query for the HTTP API."
  value       = local.amp_query_endpoint
}

output "amp_region" {
  description = "Region the AMP workspace lives in (null if metrics are disabled). May differ from the cluster's region when amp_region is set."
  value       = var.metrics_enabled ? local.amp_region : null
}

output "metrics_namespace" {
  description = "Kubernetes namespace the metrics components are installed into (null if metrics are disabled)."
  value       = var.metrics_enabled ? local.metrics_namespace : null
}

output "amp_remote_write_role_arn" {
  description = "ARN of the collector's Pod Identity role, scoped to aps:RemoteWrite on this workspace alone (null if metrics are disabled)."
  value       = var.metrics_enabled ? module.amp_remote_write_role[0].role_arn : null
}

output "otel_collector_chart_version" {
  description = "Installed version of the opentelemetry-collector Helm chart (null if metrics are disabled)."
  value       = var.metrics_enabled ? helm_release.otel_collector[0].version : null
}

output "kube_state_metrics_chart_version" {
  description = "Installed version of the kube-state-metrics Helm chart (null if not installed)."
  value       = local.kube_state_metrics_install ? helm_release.kube_state_metrics[0].version : null
}

################################################################################
# Grafana read access
################################################################################

output "grafana_role_arn" {
  description = "ARN of the role Amazon Managed Grafana assumes to query the AMP workspace and read the Container Insights log groups (null if disabled)."
  value       = var.grafana_role_enabled ? module.grafana_role[0].role_arn : null
}
