################################################################################
# EKS Cluster
################################################################################

module "cluster" {
  source = "./modules/eks_cluster"

  name               = var.name
  kubernetes_version = var.kubernetes_version

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  public_endpoint_access_enabled  = var.public_endpoint_access_enabled
  private_endpoint_access_enabled = var.private_endpoint_access_enabled
  public_access_cidrs             = var.public_access_cidrs
  service_ipv4_cidr               = var.service_ipv4_cidr
  ip_family                       = var.ip_family

  additional_cluster_security_group_ingress    = var.additional_cluster_security_group_ingress
  additional_cluster_security_group_ingress_sg = var.additional_cluster_security_group_ingress_sg

  cluster_creator_admin_permissions_enabled = var.cluster_creator_admin_permissions_enabled
  access_entries                            = var.access_entries

  enabled_cluster_log_types     = var.enabled_cluster_log_types
  cluster_log_retention_in_days = var.cluster_log_retention_in_days

  secrets_encryption_enabled = var.secrets_encryption_enabled
  secrets_kms_key_arn        = var.secrets_kms_key_arn

  vpc_cni_addon_version                 = var.vpc_cni_addon_version
  vpc_cni_addon_configuration_values    = var.vpc_cni_addon_configuration_values
  kube_proxy_addon_version              = var.kube_proxy_addon_version
  kube_proxy_addon_configuration_values = var.kube_proxy_addon_configuration_values

  pod_identity_agent_enabled       = var.pod_identity_agent_enabled
  pod_identity_agent_addon_version = var.pod_identity_agent_addon_version

  lb_controller_pod_identity_enabled = var.lb_controller_pod_identity_enabled
  lb_controller_namespace            = var.lb_controller_namespace
  lb_controller_service_account      = var.lb_controller_service_account

  pod_identity_associations = var.pod_identity_associations

  deletion_protection_enabled = var.deletion_protection_enabled

  tags = local.tags
}
