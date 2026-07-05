#!/bin/bash
# Bootstrap for ${name} EC2 service instances (${runtime} runtime).
# Runs once at launch. Deploys are pushed separately through SSM Run
# Command, so this script only prepares the host.
set -euo pipefail

dnf install -y jq unzip

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

%{ if runtime == "container" ~}
dnf install -y docker
systemctl enable --now docker
%{ else ~}
# Manual runtime: deploys run user-provided commands through SSM Run
# Command. Write the app env file once at boot so commands and apps can
# source ${env_file_path}; deploy commands may rewrite it. Prepare the
# conventional app log path and ship it to CloudWatch so apps that
# write there show up in the logs UI.
${env_file_script}

mkdir -p "$(dirname ${app_log_path})"
touch ${app_log_path}
chmod 666 ${app_log_path}

dnf install -y amazon-cloudwatch-agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/app-logs.json <<'CWCONFIG'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "${app_log_path}",
            "log_group_name": "${log_group_name}",
            "log_stream_name": "instance/{instance_id}/app",
            "timezone": "UTC"
          }
        ]
      }
    }
  }
}
CWCONFIG
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/app-logs.json
%{ endif ~}

%{ if additional_user_data != "" ~}
# Additional user data
${additional_user_data}
%{ endif ~}
