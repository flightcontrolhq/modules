#!/bin/bash
# Bootstrap for ${name} EC2 service instances.
# Runs once at launch. Deploys are pushed separately through SSM Run
# Command, so this script prepares the host for either deploy mode.
set -euo pipefail

dnf install -y git jq unzip

%{ if data_volume_creation_enabled ~}
# Resolve the configured Xen device to its Nitro NVMe alias when needed.
DATA_DEVICE="${data_volume_device_name}"
if [ ! -b "$DATA_DEVICE" ]; then
  DATA_DEVICE=$(readlink -f "${data_volume_device_name}" 2>/dev/null || true)
fi
if [ ! -b "$DATA_DEVICE" ]; then
  EXPECTED_DEVICE="f"
  DATA_DEVICE=$(for dev in /dev/nvme*n1; do
    [ -b "$dev" ] || continue
    if /sbin/ebsnvme-id "$dev" 2>/dev/null | grep -Eiq "((device name|block device mapping):[[:space:]]*)?(/dev/)?(xvd)?$${EXPECTED_DEVICE}([[:space:]]|$)"; then
      echo "$dev"
      break
    fi
  done)
fi
if [ -n "$DATA_DEVICE" ] && [ -b "$DATA_DEVICE" ]; then
  DATA_FSTYPE=$(lsblk -no FSTYPE "$DATA_DEVICE" | tr -d '[:space:]')
  if [ -z "$DATA_FSTYPE" ]; then
    mkfs -t xfs "$DATA_DEVICE"
    DATA_FSTYPE="xfs"
  fi
  mkdir -p "${data_volume_mount_path}"
  DATA_UUID=$(blkid -s UUID -o value "$DATA_DEVICE")
  sed -i "\|[[:space:]]${data_volume_mount_path}[[:space:]]|d" /etc/fstab
  echo "UUID=$${DATA_UUID} ${data_volume_mount_path} $${DATA_FSTYPE} defaults,nofail 0 2" >> /etc/fstab
  mount "${data_volume_mount_path}" || mount -a
fi
%{ endif ~}

%{ if efs_enabled ~}
# Mount the EFS file system
dnf install -y amazon-efs-utils
mkdir -p ${efs_mount_path}
%{ if efs_access_point_id != "" ~}
echo "${efs_file_system_id} ${efs_mount_path} efs _netdev,tls,accesspoint=${efs_access_point_id} 0 0" >> /etc/fstab
%{ else ~}
echo "${efs_file_system_id} ${efs_mount_path} efs _netdev,tls 0 0" >> /etc/fstab
%{ endif ~}
mount -a -t efs
%{ endif ~}

%{ if backup_dump_enabled ~}
# Install the AWS CLI only for S3 logical dump destinations.
%{ if backup_dump_destination == "s3" ~}
dnf install -y awscli
%{ endif ~}
mkdir -p "/var/log/ravion/${name}" /var/lib/ravion
cat > "/usr/local/bin/${name}-backup" <<'RAVION_BACKUP_SCRIPT'
${backup_dump_script}
RAVION_BACKUP_SCRIPT
chmod 700 "/usr/local/bin/${name}-backup"

%{ if backup_dump_restore_enabled ~}
if [ ! -f "${backup_dump_restore_marker}" ]; then
  "/usr/local/bin/${name}-backup" restore-latest
  touch "${backup_dump_restore_marker}"
fi
%{ endif ~}

cat > "/etc/systemd/system/${name}-backup.service" <<'RAVION_BACKUP_SERVICE'
[Unit]
Description=Logical backup for ${name}
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/${name}-backup backup-now
RAVION_BACKUP_SERVICE

cat > "/etc/systemd/system/${name}-backup.timer" <<'RAVION_BACKUP_TIMER'
[Unit]
Description=Logical backup schedule for ${name}

[Timer]
OnCalendar=${backup_dump_schedule}
Persistent=true
Unit=${name}-backup.service

[Install]
WantedBy=timers.target
RAVION_BACKUP_TIMER

systemctl daemon-reload
systemctl enable --now "${name}-backup.timer"
%{ endif ~}

mkdir -p "$(dirname ${env_file_path})"

# Install both runtime prerequisites so deploy mode can change without
# replacing the instance group. The same idempotent supervisor bootstrap
# also runs during deploys to upgrade existing instances in place.
dnf install -y docker
systemctl enable --now docker
${supervisor_install_script}

# Initialize the app env file. Deploys refresh it before running either mode.
${env_file_script}

dnf install -y amazon-cloudwatch-agent

%{ if additional_user_data != "" ~}
# Additional user data
${additional_user_data}
%{ endif ~}
