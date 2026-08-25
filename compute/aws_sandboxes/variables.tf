################################################################################
# Identity
################################################################################

variable "pool_id" {
  type        = string
  description = "The SandboxPool id. Used to name every resource and to key the `ravion:pool` tag the reconciler filters on."

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,62}[A-Za-z0-9]$", var.pool_id))
    error_message = "The pool_id must be 2-64 alphanumeric characters, underscores or hyphens and must not start or end with a separator."
  }
}

variable "env_slug" {
  type        = string
  description = "The environment slug. Appears in the ingress domain (`sbx.<env_slug>.<domain>`), the snapshots bucket name and the default private zone name."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,30}[a-z0-9]$", var.env_slug))
    error_message = "The env_slug must be 2-32 lowercase alphanumeric characters or hyphens and must not start or end with a hyphen."
  }
}

variable "region" {
  type        = string
  description = "AWS region. When null, the provider's configured region is used."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to all resources."
  default     = {}
}

################################################################################
# Network — from the pool's ExecutionEnvironment
################################################################################

variable "execution_environment" {
  type = object({
    vpc_id            = string
    subnet_ids        = list(string)
    security_group_id = string
  })
  description = <<-EOT
    The org-level ExecutionEnvironment the pool runs in — the same object runners
    use. The module layers its own SG on top of `security_group_id` rather than
    replacing it, and launches hosts into `subnet_ids`. In `vpc-ip` network mode
    these subnets must be large enough for prefix delegation (a /22 per pool is
    comfortable: each host takes /28 IPv4 prefixes off its ENI).
  EOT

  validation {
    condition     = can(regex("^vpc-", var.execution_environment.vpc_id))
    error_message = "The execution_environment.vpc_id must be a valid VPC ID starting with 'vpc-'."
  }

  validation {
    condition     = length(var.execution_environment.subnet_ids) > 0
    error_message = "At least one subnet ID is required in execution_environment.subnet_ids."
  }

  validation {
    condition     = alltrue([for s in var.execution_environment.subnet_ids : can(regex("^subnet-", s))])
    error_message = "All execution_environment.subnet_ids must be valid subnet IDs starting with 'subnet-'."
  }

  validation {
    condition     = can(regex("^sg-", var.execution_environment.security_group_id))
    error_message = "The execution_environment.security_group_id must be a valid security group ID starting with 'sg-'."
  }
}

variable "nlb_subnet_ids" {
  type        = list(string)
  description = "Subnets for the NLB. Defaults to the execution environment's subnets; set this to public subnets when `ingress.internet_facing` is true and the execution environment is private."
  default     = null

  validation {
    condition     = var.nlb_subnet_ids == null || alltrue([for s in coalesce(var.nlb_subnet_ids, []) : can(regex("^subnet-", s))])
    error_message = "All nlb_subnet_ids must be valid subnet IDs starting with 'subnet-'."
  }
}

variable "network_mode" {
  type        = string
  description = <<-EOT
    How a sandbox gets its network identity (plan §2.2a):
      vpc-ip — each sandbox owns a VPC private IP taken from the host ENI's
               delegated prefixes; egress leaves with the sandbox's own source
               IP, and in-VPC clients reach it on any port. Requires the ENI
               IP-management permissions this module grants in this mode.
      nat    — private 10.200.x.x per sandbox behind host-IP port remapping.
               Use where subnet space is scarce.
  EOT
  default     = "vpc-ip"

  validation {
    condition     = contains(["vpc-ip", "nat"], var.network_mode)
    error_message = "The network_mode must be 'vpc-ip' or 'nat'."
  }
}

variable "ipv6_enabled" {
  type        = bool
  description = "Give sandboxes IPv6 as well as IPv4 (adds the IPv6 ENI permissions, a dualstack NLB and an AAAA ingress record). The pool subnets must already carry an IPv6 CIDR."
  default     = false
}

################################################################################
# Ingress
################################################################################

variable "ingress" {
  type = object({
    domain          = string
    hosted_zone_id  = optional(string)
    internet_facing = optional(bool, true)
    allowed_cidrs   = optional(list(string), ["0.0.0.0/0"])
  })
  description = <<-EOT
    Public ingress for the HTTP proxy. Sandboxes are addressed as
    `<sandboxId>-<port>.sbx.<env_slug>.<domain>`.

      domain          — the customer's apex/delegated domain, e.g. `example.com`.
      hosted_zone_id  — Route 53 zone to write the wildcard alias and the ACM
                        validation records into. Omit for an externally hosted
                        zone: the records are then emitted as the
                        `acm_validation_records` output for the operator to add.
      internet_facing — false makes the NLB internal (VPC/VPN reach only).
      allowed_cidrs   — who may reach the NLB on 443.
  EOT

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.ingress.domain))
    error_message = "The ingress.domain must be a valid DNS name, e.g. 'example.com'."
  }

  validation {
    condition     = length(coalesce(var.ingress.allowed_cidrs, ["0.0.0.0/0"])) > 0
    error_message = "At least one CIDR is required in ingress.allowed_cidrs."
  }
}

variable "private_zone_name" {
  type        = string
  description = "Name of the private hosted zone that carries per-sandbox records in `vpc-ip` mode. Defaults to `sbx.<env_slug>.internal`. Must carry an `sbx` label: the customer IAM policy scopes route53:ChangeResourceRecordSets by record name, and a zone without one has its per-sandbox writes denied at runtime."
  default     = null

  validation {
    # ravion-iam 1.0.47 gates record writes on
    # route53:ChangeResourceRecordSetsNormalizedRecordNames matching `sbx.*`
    # or `*.sbx.*`. Catching a non-matching zone name at plan time is much
    # kinder than an AccessDenied on the first sandbox to come up.
    condition     = var.private_zone_name == null || can(regex("(^|\\.)sbx\\.", var.private_zone_name))
    error_message = "The private_zone_name must contain an `sbx` label (e.g. sbx.example.internal); the customer IAM policy scopes per-sandbox DNS writes by record name."
  }
}

variable "proxy_port" {
  type        = number
  description = "The port the host ingress proxy listens on. The NLB's TLS listener forwards to it."
  default     = 8443

  validation {
    condition     = var.proxy_port >= 1 && var.proxy_port <= 65535
    error_message = "The proxy_port must be between 1 and 65535."
  }
}

variable "ssl_policy" {
  type        = string
  description = "TLS policy for the NLB's 443 listener."
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "enable_tcp_exposure" {
  type        = bool
  description = "Create the NLB IP-target group used to expose arbitrary sandbox TCP ports, and pre-authorise `tcp_exposure_port_range` through the NLB and host security groups. Tower adds the per-port listeners at runtime."
  default     = true
}

variable "tcp_exposure_port_range" {
  type = object({
    from = number
    to   = number
  })
  description = "Port range pre-authorised on the NLB and host security groups for TCP exposure. Ports with no listener are still dropped by the NLB; this is the envelope Tower may register within, not an open door."
  default     = { from = 1024, to = 65535 }

  validation {
    condition     = var.tcp_exposure_port_range.from >= 1 && var.tcp_exposure_port_range.to <= 65535 && var.tcp_exposure_port_range.from <= var.tcp_exposure_port_range.to
    error_message = "The tcp_exposure_port_range must be a valid ascending range within 1-65535."
  }
}

variable "internal_access_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to reach sandbox IPs directly on any TCP port (VPN, peered VPCs, bastion subnets). Only meaningful in `vpc-ip` mode; empty means in-VPC clients reach sandboxes only through the NLB."
  default     = []

  validation {
    condition     = alltrue([for cidr in var.internal_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "All internal_access_cidrs must be valid IPv4 CIDR blocks."
  }
}

################################################################################
# Hosts
################################################################################

variable "host_ami_id" {
  type        = string
  description = "The Ravion sandbox host AMI, shared to this account for this region. Pinned by version: rollout is a new launch-template version plus a reconciler replace."

  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.host_ami_id))
    error_message = "The host_ami_id must be a valid AMI ID starting with 'ami-'."
  }
}

variable "host_instance_types" {
  type        = list(string)
  description = <<-EOT
    Instance types the reconciler may launch, most-preferred first. The launch
    template pins the first one; the rest are passed as EC2 Fleet overrides by
    the reconciler, which is why they are only exported, never rendered into a
    resource here. All of them must support nested virtualisation
    (8th-gen Intel: c8i / m8i / r8i and their flex variants) or be bare metal.
  EOT
  default     = ["m8i.2xlarge"]

  validation {
    condition     = length(var.host_instance_types) > 0
    error_message = "At least one instance type is required in host_instance_types."
  }
}

variable "max_ip_prefixes" {
  type        = number
  description = <<-EOT
    Caps how many /28 prefixes a host delegates to its primary ENI, below the
    instance type's own limit. For pools whose subnet is smaller than their
    hosts: the instance type's limit is what EC2 allows, not what the subnet
    can spare, and a host that allocates past the subnet fails mid-create on a
    sandbox the scheduler has already committed to. Null means the instance
    type's limit. Only meaningful when network_mode = "vpc-ip".
  EOT
  default     = null

  validation {
    condition     = var.max_ip_prefixes == null || var.max_ip_prefixes > 0
    error_message = "The max_ip_prefixes must be null (the instance type's limit) or a positive number."
  }
}

variable "nested_virtualization" {
  type        = string
  description = "Exposes VT-x to the host OS, i.e. creates /dev/kvm. Opt-in per instance and only on 8th-gen Intel. Set to 'disabled' only for bare-metal instance types, which have KVM natively."
  default     = "enabled"

  validation {
    condition     = contains(["enabled", "disabled"], var.nested_virtualization)
    error_message = "The nested_virtualization must be 'enabled' or 'disabled'."
  }
}

variable "root_volume_size_gb" {
  type        = number
  description = "Root EBS volume size for hosts: OS, firecracker, guest kernels and the host agent."
  default     = 100

  validation {
    condition     = var.root_volume_size_gb >= 20
    error_message = "The root_volume_size_gb must be at least 20."
  }
}

variable "cache_volume_size_gb" {
  type        = number
  description = "Size of the chunk-cache data volume (XFS with reflink: snapshot chunks, reflinked rootfs, jailer chroots). Purely a cache of the S3 chunk store, so it is destroyed with the host."
  default     = 500

  validation {
    condition     = var.cache_volume_size_gb >= 50
    error_message = "The cache_volume_size_gb must be at least 50."
  }
}

variable "cache_volume_device_name" {
  type        = string
  description = "Block device name for the chunk-cache volume. Handed to the host agent via /etc/ravion/sandbox-host.env."
  default     = "/dev/xvdb"
}

variable "cache_volume_iops" {
  type        = number
  description = "gp3 IOPS for the chunk-cache volume. null keeps the included 3000 baseline."
  default     = null
}

variable "cache_volume_throughput" {
  type        = number
  description = "gp3 throughput (MB/s) for the chunk-cache volume. null keeps the included 125. Snapshot restore is throughput-bound, so raise it before raising IOPS."
  default     = null
}

variable "root_volume_type" {
  type        = string
  description = "EBS volume type for the host root volume."
  default     = "gp3"
}

variable "host_allow_all_egress" {
  type        = bool
  description = "Allow hosts (and, in `vpc-ip` mode, the sandbox IPs riding on their ENIs) unrestricted egress. Left false, the host SG permits only the ports in `host_egress_ports`; per-sandbox egress policy is enforced on the host by nftables either way."
  default     = false
}

variable "host_egress_ports" {
  type        = list(number)
  description = "TCP ports hosts may egress to when `host_allow_all_egress` is false. UDP/53 is always allowed so the sandbox-aware resolver can work."
  default     = [443]
}

variable "host_egress_cidrs" {
  type        = list(string)
  description = "Destination CIDRs for host egress."
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for cidr in var.host_egress_cidrs : can(cidrhost(cidr, 0))])
    error_message = "All host_egress_cidrs must be valid IPv4 CIDR blocks."
  }
}

variable "attach_ssm_managed_policy" {
  type        = bool
  description = "Attach AmazonSSMManagedInstanceCore to the host role so operators can open a Session Manager shell on a host without SSH or a bastion."
  default     = true
}

################################################################################
# Storage & observability
################################################################################

variable "snapshot_retention_days" {
  type        = number
  description = "Days before an unpinned snapshot object expires from the snapshots bucket. Objects tagged `ravion:pinned=true` (prewarm bases, fork parents) are exempt."
  default     = 30

  validation {
    condition     = var.snapshot_retention_days >= 1
    error_message = "The snapshot_retention_days must be at least 1."
  }
}

variable "log_retention_days" {
  type        = number
  description = "Retention for the host and sandbox log groups."
  default     = 30
}

variable "ravion_role_arn" {
  type        = string
  description = "ARN of the Ravion cross-account role. When set it is granted read/write on the snapshots bucket so the control plane can seed prewarm images and garbage-collect."
  default     = null

  validation {
    condition     = var.ravion_role_arn == null || can(regex("^arn:aws:iam::[0-9]{12}:role/", var.ravion_role_arn))
    error_message = "The ravion_role_arn must be a valid IAM role ARN."
  }
}

variable "force_destroy_snapshots_bucket" {
  type        = bool
  description = "Allow `destroy` to delete a non-empty snapshots bucket. Snapshots are a cache, but a pool teardown that loses prewarm bases costs a cold rebuild, so this is off by default."
  default     = false
}

################################################################################
# VPC endpoints
################################################################################

################################################################################
# Certificate validation
################################################################################

variable "wait_for_certificate_validation" {
  type        = bool
  description = "Block the apply until the wildcard certificate is ISSUED. Leave true: an ELB listener cannot attach a pending certificate. Set false only when the certificate is known to be issued already and the wait is dead time."
  default     = true
}

variable "acm_validation_timeout" {
  type        = string
  description = "How long to wait for certificate validation. With an externally hosted zone this is the window in which an operator must add the records reported by `acm_validation_records`."
  default     = "45m"
}
