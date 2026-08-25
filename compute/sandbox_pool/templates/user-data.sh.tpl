#!/usr/bin/env bash
# Rendered by the ravion/sandbox-pool Terraform module.
#
# Everything a host needs to know about its pool that it cannot discover from
# IMDS. Host prep itself — kvm group, firecracker, jailer chroot base, nftables
# — is baked into the AMI (plan §2.8); this file only writes configuration and
# starts the agent, so a host is useful within a second of boot.
set -euo pipefail

install -d -m 0755 /etc/ravion

# Three of the host's settings are properties of THIS box, not of the pool, and
# so cannot be rendered by Terraform:
#
#   * the resolver address must be an address the guests can route to, which is
#     the host's own ENI address — a different one per instance;
#   * the uplink is whichever NIC carries the default route;
#   * the instance type is a fleet override, so the launch template's own
#     instance_type is only the first candidate and is routinely not what
#     booted.
#
# The agent falls back to IMDS for the instance type and refuses to start the
# resolver without an address, so this block is what turns egress allow-lists
# with domains in them from silently-empty into working.
IMDS_TOKEN="$(curl -sS -X PUT -m 2 -H 'X-aws-ec2-metadata-token-ttl-seconds: 300' http://169.254.169.254/latest/api/token || true)"
imds() {
  curl -sS -m 2 -H "X-aws-ec2-metadata-token: $${IMDS_TOKEN}" "http://169.254.169.254/latest/meta-data/$1" || true
}
HOST_IPV4="$(imds local-ipv4)"
HOST_INSTANCE_TYPE="$(imds instance-type)"
UPLINK_IFACE="$(ip -o route get 169.254.169.254 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "dev") print $(i + 1)}' | head -n1)"

cat > /etc/ravion/sandbox-host.env <<'RAVION_ENV'
RAVION_POOL_ID=${pool_id}
RAVION_ENV_SLUG=${env_slug}
RAVION_REGION=${region}
RAVION_SSM_PARAM_PREFIX=${ssm_param_prefix}
RAVION_SNAPSHOTS_BUCKET=${snapshots_bucket}
RAVION_PROXY_PORT=${proxy_port}
RAVION_NETWORK_MODE=${network_mode}
RAVION_IPV6_ENABLED=${ipv6_enabled}
RAVION_PRIVATE_ZONE_ID=${private_zone_id}
RAVION_PRIVATE_ZONE_NAME=${private_zone_name}
RAVION_INGRESS_DOMAIN=${ingress_domain}
RAVION_HOST_LOG_GROUP=${host_log_group}
RAVION_SANDBOX_LOG_GROUP=${sandbox_log_group}
RAVION_CACHE_DEVICE=${cache_device}
RAVION_TARGET_GROUP_ARN=${target_group_arn}
RAVION_TCP_TARGET_GROUP_ARN=${tcp_target_group_arn}
RAVION_MAX_IP_PREFIXES=${max_ip_prefixes}
RAVION_ENV

# Appended rather than templated: these are per-instance, discovered above.
# An empty value is written as an empty value on purpose — the agent treats
# "unset" and "empty" the same way and each has a defined safe behaviour.
cat >> /etc/ravion/sandbox-host.env <<RAVION_HOST_ENV
RAVION_DNS_RESOLVER_ADDR=$${HOST_IPV4}
RAVION_UPLINK_IFACE=$${UPLINK_IFACE}
RAVION_INSTANCE_TYPE=$${HOST_INSTANCE_TYPE}
RAVION_HOST_ENV

chmod 0644 /etc/ravion/sandbox-host.env

# The chunk cache. XFS with reflink is not a preference: reflinked rootfs
# copies are how a clone costs milliseconds instead of a full copy.
CACHE_DEV="${cache_device}"
if [ -b "$${CACHE_DEV}" ]; then
  if ! blkid "$${CACHE_DEV}" >/dev/null 2>&1; then
    mkfs.xfs -m reflink=1 -f "$${CACHE_DEV}"
  fi
  install -d -m 0755 /var/lib/ravion/cache
  grep -q "^$${CACHE_DEV}[[:space:]]" /etc/fstab ||
    echo "$${CACHE_DEV} /var/lib/ravion/cache xfs defaults,noatime,nofail 0 2" >> /etc/fstab
  mount -a
fi

# systemd units ship in the AMI; they read the env file written above.
systemctl daemon-reload
systemctl enable --now ravion-sandbox-host.service
