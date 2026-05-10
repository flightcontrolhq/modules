# EKS Cluster

Provisions an Amazon EKS cluster control plane with the pieces every cluster
actually needs:

- The cluster itself, with `authentication_mode = API` (no aws-auth ConfigMap).
- An IAM service role for the control plane.
- An OIDC identity provider for IRSA-based workloads.
- Optional KMS envelope encryption for Kubernetes secrets (default on).
- Optional CloudWatch control-plane logging with a managed log group (default on).
- Core add-ons: `vpc-cni`, `coredns`, `kube-proxy`.
- Optional add-ons: `eks-pod-identity-agent` (default on), `aws-ebs-csi-driver`.
- A Pod Identity role + association for the AWS Load Balancer Controller (consumer Helm-installs the controller).
- A Pod Identity role + association for the EBS CSI driver (when enabled).
- Caller-driven access entries (`var.access_entries`) and pod identity associations (`var.pod_identity_associations`).

Node groups, Fargate profiles, and Karpenter are separate modules
(`kubernetes/eks_node_group`, `kubernetes/eks_fargate_profile`,
`kubernetes/eks_karpenter`).

## Usage

```hcl
module "eks" {
  source = "git::https://github.com/flightcontrolhq/modules.git//kubernetes/eks_cluster?ref=v1.0.0"

  name               = "platform"
  kubernetes_version = "1.31"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  endpoint_public_access  = true
  endpoint_private_access = true

  enable_ebs_csi_driver         = true
  enable_pod_identity_agent     = true
  enable_lb_controller_pod_identity = true

  access_entries = {
    "platform-admins" = {
      principal_arn = "arn:aws:iam::123456789012:role/PlatformAdmins"
      policy_associations = {
        "cluster-admin" = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  tags = { Environment = "prod" }
}
```

## Requirements

| Name               | Version    |
| ------------------ | ---------- |
| opentofu/terraform | >= 1.10.0  |
| aws                | >= 5.0     |
| tls                | >= 4.0     |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name of the EKS cluster. | `string` | n/a | yes |
| kubernetes_version | Kubernetes version (`MAJOR.MINOR`). | `string` | `null` | no |
| vpc_id | VPC ID to launch the control plane ENIs into. | `string` | n/a | yes |
| subnet_ids | Subnets for control plane ENIs (>=2, multi-AZ). | `list(string)` | n/a | yes |
| endpoint_public_access | Expose the API server publicly. | `bool` | `false` | no |
| endpoint_private_access | Expose the API server inside the VPC. | `bool` | `true` | no |
| public_access_cidrs | CIDRs allowed to hit the public endpoint. | `list(string)` | `["0.0.0.0/0"]` | no |
| service_ipv4_cidr | Override the service CIDR (IPv4 only). | `string` | `null` | no |
| ip_family | `ipv4` or `ipv6`. | `string` | `"ipv4"` | no |
| additional_cluster_security_group_ingress | Extra cluster-SG ingress rules sourced by IPv4 CIDR. | `list(object)` | `[]` | no |
| additional_cluster_security_group_ingress_sg | Extra cluster-SG ingress rules sourced by another SG. | `list(object)` | `[]` | no |
| bootstrap_cluster_creator_admin_permissions | Auto-grant cluster-admin to the creating principal. | `bool` | `true` | no |
| access_entries | EKS access entries to create (replaces aws-auth ConfigMap). | `map(object)` | `{}` | no |
| enabled_cluster_log_types | Control plane log types to ship to CloudWatch. | `list(string)` | `["api","audit","authenticator"]` | no |
| cluster_log_retention_in_days | Retention for the control plane log group. | `number` | `30` | no |
| enable_secrets_encryption | Envelope-encrypt Kubernetes secrets with KMS. | `bool` | `true` | no |
| secrets_kms_key_arn | Existing KMS key ARN; null = create one. | `string` | `null` | no |
| vpc_cni_addon_version / coredns_addon_version / kube_proxy_addon_version | Pinned add-on versions. | `string` | `null` | no |
| vpc_cni_addon_configuration_values / coredns_addon_configuration_values / kube_proxy_addon_configuration_values | JSON config overrides. | `string` | `null` | no |
| enable_ebs_csi_driver | Install aws-ebs-csi-driver + Pod Identity role. | `bool` | `false` | no |
| ebs_csi_addon_version | Pin EBS CSI add-on version. | `string` | `null` | no |
| enable_pod_identity_agent | Install eks-pod-identity-agent. | `bool` | `true` | no |
| pod_identity_agent_addon_version | Pin pod identity agent add-on version. | `string` | `null` | no |
| enable_lb_controller_pod_identity | Create LB Controller Pod Identity role/association. | `bool` | `true` | no |
| lb_controller_namespace | Namespace of the LB Controller SA. | `string` | `"kube-system"` | no |
| lb_controller_service_account | Name of the LB Controller SA. | `string` | `"aws-load-balancer-controller"` | no |
| pod_identity_associations | Extra `{ namespace, service_account, role_arn }` associations. | `map(object)` | `{}` | no |
| tags | Tags applied to all created resources. | `map(string)` | `{}` | no |
| region | AWS region override. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| cluster_id / cluster_arn / cluster_name | Cluster identifiers. |
| cluster_endpoint | Kubernetes API server URL. |
| cluster_certificate_authority_data | Base64 CA cert for kubeconfig. |
| cluster_version / cluster_platform_version / cluster_status | Cluster state. |
| cluster_security_group_id / cluster_vpc_config | Networking outputs. |
| cluster_iam_role_arn / cluster_iam_role_name | Control plane service role. |
| oidc_issuer_url / oidc_issuer_host / oidc_provider_arn | IRSA wiring for consumer workloads. |
| secrets_kms_key_arn | Secrets KMS key (null if disabled). |
| cloudwatch_log_group_name / cloudwatch_log_group_arn | Control plane log group. |
| lb_controller_role_arn / lb_controller_role_name | LB Controller Pod Identity role. |
| ebs_csi_role_arn / ebs_csi_role_name | EBS CSI Pod Identity role. |
| aws_account_id / region | Account & region info. |

## Notes

- The OIDC provider's thumbprint is taken from the cluster's TLS chain at apply time; AWS recommends this approach over hardcoding the well-known thumbprint.
- The LB Controller's IAM policy is vendored from `kubernetes-sigs/aws-load-balancer-controller` upstream (`docs/install/iam_policy.json`) at `policies/lb_controller.json`. Refresh that file when you upgrade the controller version.
- Pod Identity needs the `eks-pod-identity-agent` add-on. Disabling it (`enable_pod_identity_agent = false`) without disabling the helper roles will leave their associations created but non-functional at runtime.
