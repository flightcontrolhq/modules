#!/bin/bash
# Bootstrap for ${name} EC2 service instances.
# Runs once at launch. Deploys are pushed separately through SSM Run
# Command, so this script prepares the host for either deploy mode.
set -euo pipefail

dnf install -y git jq unzip

%{ if data_volume_enabled ~}
# Format and mount the data volume on first boot. The volume is the only
# attached disk without a filesystem; on later boots fstab mounts it.
DATA_DEVICE=""
for dev in $(lsblk -dnpo NAME -e 7,11); do
  if [ -z "$(lsblk -no FSTYPE "$dev" | tr -d '[:space:]')" ]; then
    DATA_DEVICE="$dev"
    break
  fi
done
if [ -n "$DATA_DEVICE" ]; then
  mkfs -t xfs "$DATA_DEVICE"
  mkdir -p ${data_volume_mount_path}
  DATA_UUID=$(blkid -s UUID -o value "$DATA_DEVICE")
  echo "UUID=$DATA_UUID ${data_volume_mount_path} xfs defaults,nofail 0 2" >> /etc/fstab
  mount -a
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
