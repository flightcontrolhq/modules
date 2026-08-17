# EC2 Service

Runs an app on a stable group of EC2 instances behind an optional Application Load Balancer, with in-place deploys pushed through SSM Run Command. Instances are managed by an Auto Scaling Group but are never replaced by deploys, so per-instance state (root volume, optional data volume) persists for the life of each instance.

Two runtimes are supported:

- **container** — each deploy pulls an image and runs the attached Docker process under supervisord.
- **manual** — deploys can check out an authenticated Git source, run release preparation commands, then start the configured long-lived command under supervisord.

Instances install the prerequisites for both runtimes at launch, so `runtime` can switch between `container` and `manual` without replacing the instance group. Supervisord owns the app in both modes and restarts it after an unexpected exit.

Container workloads that need to orchestrate sibling containers can enable `docker_socket_mount_enabled`. The deploy runner then bind-mounts `/var/run/docker.sock` at the identical path inside the app container and adds the host `docker` group's GID at container-start time. The image must include a `docker` CLI. This is Docker-outside-of-Docker: mounting the host Docker socket grants the container root-equivalent control of the instance, including the ability to start privileged containers, read the host filesystem, and use the instance role. Leave it disabled unless this level of access is required.

## How deploys work

For the **container** runtime the module creates an SSM Command document (`<name>-deploy` — the name is a platform contract derived from the group name) that encodes the whole in-place deploy for one instance:

1. Rebuild the app env file: Terraform-rendered plain values, plus secret values fetched on the instance from Secrets Manager / SSM Parameter Store.
2. Drain: deregister the instance from the target group and wait (skipped in worker mode, and when the instance is the only registered target — with nothing to shift traffic to, draining only lengthens the outage).
3. Swap the release: `docker pull`, then update the supervisord-managed container process.
4. Health gate: poll `http://localhost:<app_port><deploy_health_check_path>` until healthy, or fail the command.
5. Re-register the instance with the target group and wait until in service.

An orchestrator (the Ravion deploy manager) runs this document against the Auto Scaling Group's instances with its own batching and failure policy, passing:

| Parameter | Value |
|-----------|-------|
| `imageUri` | Full image URI including tag or digest |
| `deployId` | Optional release identifier |

The module definition exposes the rolling deployment batch and failure limits. It defaults to one instance at a time and stops after the first failure. The SSM script timeout applies per instance; the module deployment has a separate 24-hour overall safety limit.

For the **manual** runtime the document (same `<name>-deploy` name) takes a `commands` parameter and an optional Git source. When source is present, the instance fetches a temporary credential from SSM Parameter Store, performs a clean checkout under `/srv/ravion/<name>/source`, and runs both the preparation commands and `manual_start_command` from the selected base path. When source is absent, commands keep their existing working-directory behavior. Any failure stops the deploy. The start command must remain in the foreground rather than daemonizing. Draining and health checking are up to the preparation commands.

App stdout and stderr are shipped to `/ravion/ec2/<name>`. Streams use `deployment/<deployId>/instance/<instance-id>`, which keeps every deployment and EC2 instance separate. The SSM deploy script tees its stdout and stderr into the same instance stream while preserving the native SSM command output.

New instances launched by the Auto Scaling Group boot from the launch template but hold no release until the orchestrator repeats the deploy against them.

## App log rotation

Supervisord rotates the on-instance app log rather than letting a crash-looping process fill the root volume: `log_rotation_max_size_mb` (default 20) and `log_rotation_backup_count` (default 5) bound on-instance usage to `(backups + 1) * max size` per deployment log. The module writes the supervisord program config on every deploy, after any deploy commands run, so these settings cannot be overridden from a deploy command; change them through the module inputs instead. Replacement instances get the same configuration from the launch template.

## Choosing an instance type

Pick the family that fits the workload, then the newest generation of that family the target region actually offers.

| Family | Memory per vCPU | Use for |
|--------|-----------------|---------|
| `t` burstable | 0.5-4 GB | Small or spiky services, development and staging environments, low-volume workers |
| `m` general purpose | 4 GB | Web services and workers with no strong CPU or memory bias |
| `c` compute optimized | 2 GB | CPU-bound work such as request-heavy APIs, transcoding, or compilation |
| `r` memory optimized | 8 GB | Memory-bound work such as large heaps, in-process caches, or a local database |

In `m8g.large`, the digit is the generation and the letters after it identify the processor: `g` is AWS Graviton (`arm64`), `i` is Intel, `a` is AMD, and older families such as `m5` or `t3` carry no processor letter. A `-flex` variant such as `m8i-flex` costs less for workloads that do not sustain high CPU.

**Always use the highest generation number available for the chosen family.** Each generation is faster and cheaper per unit of work than the one below it, so `m8g` beats `m7g`, which beats `m6i`. Do not copy an instance type from an example (including the ones below), an older project, or an AI assistant's memory — those are typically one or two generations behind current, which pays more for less performance. Query the region instead:

```sh
ravion values aws/ec2/instances --aws-account-id <account-id> --region us-east-1
```

That lists exactly what the account and region support, from the same source as the Instance type list in the Ravion config form. Newest generations reach the largest regions first, so a region can top out a generation behind, and that list is region-level: a type offered in the region may still be missing from one Availability Zone, so if capacity fails in one subnet, place the group across more AZs. Burstable is the exception to the generation rule: `t4g`, `t3`, and `t3a` are still the newest burstable families, because AWS has not released a newer one.

Prefer Graviton whenever the workload can run on it: best price and performance in every family that offers it, and with `ami_id` left null the module reads `supported_architectures` from the selected instance type and resolves the matching `arm64` Amazon Linux 2023 AMI, so no other input changes. A custom `ami_id` is used as given, so it must already match the instance type's architecture. The container image (`container` runtime) or host-installed dependencies (`manual` runtime) must build for `arm64`. Use an Intel or AMD type when something in the stack is `x86_64`-only.

Then right-size from measurement: start with the smallest size in the family that holds the working set, watch the instances' CPU and memory utilization, and move up a size or set `cpu_autoscaling_enabled` from there.

Changing `instance_type` produces a new launch template version that applies to instances launched afterwards. Running instances keep their current type until recycled, and a Graviton/x86 switch changes the AMI for new instances only, so the group can briefly run both architectures mid-recycle. Either keep multi-architecture images during that window or recycle every instance promptly.

## Usage

The instance types in these examples are illustrative, not recommendations — select yours as described above.

### Web service running a container

```hcl
module "web" {
  source = "git::https://github.com/ravionhq/modules.git//compute/ec2_service?ref=v1.0.0"

  name       = "my-web"
  vpc_id     = "vpc-0123456789abcdef0"
  subnet_ids = ["subnet-aaa", "subnet-bbb"]

  runtime       = "container"
  instance_type = "m8g.large"
  min_size      = 2
  max_size      = 4

  app_port                = 3000
  deploy_health_check_path = "/health"

  ecr_repository_creation_enabled = true

  load_balancer_attachment = {
    target_group = {
      port = 3000
      health_check = {
        path = "/health"
      }
    }
    listener_rules = [
      {
        listener_arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/shared/abc/def"
        conditions = [
          { type = "host-header", values = ["app.example.com"] }
        ]
      }
    ]
  }
  load_balancer_security_group_id = "sg-0123456789abcdef0"

  environment_variables = [
    { name = "NODE_ENV", value = "production" }
  ]
  secrets = [
    { name = "DATABASE_URL", value_from = "arn:aws:ssm:us-east-1:123456789012:parameter/my-app/database-url" }
  ]
}
```

### Worker with manual command deploys

```hcl
module "worker" {
  source = "git::https://github.com/ravionhq/modules.git//compute/ec2_service?ref=v1.0.0"

  name       = "my-worker"
  vpc_id     = "vpc-0123456789abcdef0"
  subnet_ids = ["subnet-aaa", "subnet-bbb"]

  runtime       = "manual"
  instance_type = "m8g.large"

  manual_start_command = "cd /srv/app && ./bin/worker"

  data_volume_creation_enabled = true
  data_volume_size             = 50
}
```

Deploys then run your release preparation commands on every instance, with the app env file refreshed and loaded first:

```sh
aws ssm send-command \
  --document-name my-worker-deploy \
  --targets Key=tag:aws:autoscaling:groupName,Values=my-worker \
  --parameters commands='["cd /srv/app && git pull","cd /srv/app && ./bin/migrate"]'
```

## Storage and durability

- The root volume and optional data volume are per-instance EBS. They are durable for the life of the instance: deploys, restarts, and stack updates never replace an instance, so local files such as an embedded database stay in place at local-disk latency, exactly as on an EC2 instance you launch yourself.
- They are deleted with the instance, which happens for exactly three reasons: you terminate or recycle it (for example to roll out a new AMI), the group scales in, or it fails its Auto Scaling health check. On-disk databases such as SQLite and Postgres are supported when Backups are configured; without backups, a replacement loses the volume.
- `health_check_type` defaults to `EC2`, which is the AWS instance/system status check — unreachable instance, broken boot or network state, failed underlying host. It ignores application state: a crashed app is restarted in place by supervisord, and a failing HTTP health check never replaces an instance. So health-driven replacement is rare and tied to hardware or hypervisor failure. Setting `health_check_type = "ELB"` makes load balancer health replace instances instead, which also breaks in-place deploys (they briefly deregister the instance).
- Mount an EFS file system (`efs_*` variables) when several instances must share the same files, or when a replacement instance must find data already in place; it is mounted on every instance and, for the container runtime, bind-mounted into the app container. EFS is for shared files, not a live SQLite or Postgres data directory.
- Shared or multi-attach EBS block storage is deliberately not supported. A block device is not a shared filesystem; concurrent read/write mounts of XFS or ext4 can corrupt it. Reliable multi-writer access needs a cluster filesystem and fencing, while single-writer databases gain nothing from multi-attach.
- When `docker_socket_mount_enabled` is enabled, the data volume and EFS host paths are mapped identically inside the app container. This lets sibling containers started through the host Docker socket resolve those same host-path binds correctly.
- Launch template changes (AMI, user data, volumes) intentionally apply only to newly launched instances; there is no instance refresh, so applying a new AMI never replaces running instances by itself. Recycling instances to pick up the new AMI is a replacement, and it deletes their volumes.

## Backups and restore

Enable `backup_enabled` to create a service-specific Amazon Data Lifecycle Manager schedule. The default daily snapshot uses `filesystem_freeze` when a data volume exists, which runs `sync` and freezes only the data mount (never `/` or `/boot`) while the multi-volume snapshot set is taken. Use `crash_consistent` when filesystem freezing is unsuitable, or `custom` with both pre- and post-script commands for engine-specific quiescing. A safety timeout thaws a frozen filesystem if the post-script is delayed or lost.

Snapshots are incremental EBS snapshots, but the schedule still costs storage and (for cross-region copies) transfer and destination-region storage. The honest RPO is `backup_interval_hours`: a failure immediately before a scheduled snapshot can lose up to that interval. Phase 1 has no automatic restore. The RTO requires a human operator to deliberately select a snapshot and recycle an instance; a replacement instance otherwise boots with an empty data volume.

To restore:

1. Find a snapshot using the `RavionBackup=<service name>` tag, or the `backup_snapshot_filter` output.
2. Set `data_volume_snapshot_id` to the selected `snap-...` ID while `data_volume_creation_enabled` remains enabled. Keep `data_volume_size` at least as large as the snapshot's size; the configured `data_volume_type` and size are passed to the restored volume, so AWS rejects an undersized restore instead of silently changing it.
3. Apply the change and recycle the affected instance so it launches from the snapshot.
4. Verify that the restored filesystem is mounted at `data_volume_mount_path` and that the application sees the expected data.
5. Clear `data_volume_snapshot_id` and apply again, so future replacements do not keep booting from that pinned snapshot.

## Logical dumps and replacement restore

Phase 2 adds engine-native logical dumps for per-object recovery and replacement onto a different instance, Availability Zone, or region. Enable `backup_dump_enabled`, then provide the two halves of the command contract:

- `backup_dump_command` runs as root and writes a complete logical dump into the module-created staging directory.
- `backup_dump_restore_command` runs as root and reads that directory to restore the dump.

The staging directory is exported to both commands as `RAVION_BACKUP_DIR`. The command must write its artifacts there; the module owns staging, manifests, upload/download, newest-backup discovery, and retention. For example, a SQLite command can use `.backup "$RAVION_BACKUP_DIR/app.db"`, while a PostgreSQL command can write `pg_dump` output there.

The `${name}-backup` SSM Command document provides `backup-now` and `restore-latest` actions. The same script runs from the daily systemd timer and the planned-termination automation. Each run is stored under `<prefix><service name>/<UTC timestamp>/` and contains a manifest with completion time, instance ID, and the files present. Discovery reads manifests rather than trusting key names or object metadata.

The schedule uses systemd `OnCalendar` syntax, including shorthand values such as `hourly` and `daily`. Set `backup_dump_max_interval_hours` to a value greater than the schedule interval; it controls the missing-success alarm window. The default AL2023 AMI supplies AWS CLI v2, which the S3 workflow checks for rather than attempting to install the unrelated `awscli` package.

S3 is the default destination and uses a module-created encrypted, versioned, private bucket unless `backup_dump_s3_bucket_arn` supplies an existing one. Current and noncurrent versions are expired according to `backup_dump_retention_days` for a module-created bucket. A supplied bucket is owned by the caller: the module prunes old service artifacts from it, but bucket lifecycle, versioning, and object-lock policy remain the bucket owner's responsibility. Terraform does not delete a non-empty module-created bucket unless `backup_dump_force_deletion_enabled` is explicitly enabled. EFS uses the existing EFS mount and the same layout, but costs roughly ten times S3 storage, has no versioning or object lock of its own, and is available only in the VPC. EFS is a backup destination, not a live SQLite or Postgres data directory; `rsync` of a live database file is not a valid backup.

When restore-on-first-boot is enabled, a replacement instance discovers the newest manifest, logs its exact completion timestamp and age, downloads the artifacts, runs the restore command, and writes a marker on the data volume only after success. A reboot does not restore again. A successful listing that contains no manifests is treated as a fresh service: the module logs that no restore is needed and writes the marker so the instance can initialize normally. Listing or download failures, failed restore commands, and stale backups identified by `backup_max_age_hours` remain fatal; they do not write the marker or start the application. The instance remains available for inspection rather than silently starting with stale or empty data and diverging from the backup.

Planned ASG termination can run a final dump through an EventBridge-triggered SSM Automation lifecycle hook. Its heartbeat timeout and `CONTINUE` safety result prevent a failed or slow dump from wedging the group. Hard crashes, Availability Zone loss, and instance-store failures cannot run this hook. If multiple instances restore the same dump, they then diverge independently; the feature is intentionally not gated on instance count.

Logical-dump RPO is approximately the dump schedule interval, while a planned-termination dump can provide near-zero loss for planned replacement. Restore-on-first-boot automates the workflow but still depends on the newest available dump and a successful engine restore command. Phase 1 EBS snapshot restore remains deliberate and manual for whole-volume recovery.

## Continuous replication

Phase 3 adds native Litestream support for SQLite. Enable `backup_replication_enabled`, set `backup_replication_database_path` to an absolute path under the EBS data volume, and provide an S3 bucket ARN or let the module create one. The module installs its internally pinned Litestream 0.5.12 release after verifying its architecture-specific checksum, writes a Litestream configuration with the configured full-snapshot interval and retention, and runs `litestream replicate` as a supervised program. Litestream upgrades are module releases rather than a caller-controlled input. Its log is shipped to the same CloudWatch log group as application and logical-backup logs.

When `backup_replication_restore_on_first_boot_enabled` is enabled, the first boot lists the replica's LTX files with Litestream's `ltx -level all -json` command before restoring. A successful empty listing is treated as a fresh service and marks restore complete; a non-zero discovery exit blocks startup, so credential and network failures cannot masquerade as an empty replica. Restore failures and replicas older than `backup_replication_max_age_hours` also block application startup without writing the marker. The replica is a supplement to snapshots and logical dumps, not a replacement: a corrupted SQLite database produces a corrupted replica.

Litestream is SQLite-only. Keep the live database on the local EBS data volume, not EFS. The configured replication bucket is shared with logical dumps when both features are enabled: dumps use the logical-backup prefix and replicas use their own replication prefix. Do not run multiple instances against the same SQLite database and replica prefix: the replicas will conflict or corrupt. The module intentionally does not gate replication on instance count, so the operator must enforce single-writer deployment.

PostgreSQL continuous archiving is not a module input. It requires engine-specific `archive_command` configuration in `postgresql.conf` and credentials that this module does not own. Use `additional_user_data` for a WAL-G or pgBackRest recipe and phase 1 custom consistency hooks for deliberate snapshots instead of enabling an input that would only be partially configured.

The three backup phases have different recovery characteristics:

| Phase | Mechanism | Honest RPO | Restore path |
| --- | --- | --- | --- |
| 1 | EBS snapshots | Snapshot interval | Human selects a snapshot and recycles an instance |
| 2 | Engine-native dumps | Dump interval, with near-zero loss for planned termination | Optional restore-on-first-boot |
| 3 | Litestream SQLite replication | Typically seconds, based on the snapshot interval | Optional restore-on-first-boot |

Use snapshots for whole-volume recovery, logical dumps for portable per-object recovery, and replication for low-RPO SQLite replacement recovery. Keep at least one snapshot or dump path because continuous replication preserves whatever state the source database has, including corruption.

## Requirements

| Name | Version |
|------|---------|
| opentofu/terraform | >= 1.10.0 |
| aws | >= 6.0 |

Instances need outbound access to SSM, ECR/S3, CloudWatch Logs, PyPI for the pinned Supervisor installation, and (when secrets are configured) Secrets Manager (NAT gateway, public IPs, or VPC endpoints). The default AMI is Amazon Linux 2023; custom AMIs must run cloud-init and include the SSM agent.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name prefix for all resources (1-28 chars) | `string` | n/a | yes |
| tags | Tags for all resources | `map(string)` | `{}` | no |
| region | AWS region (null = provider region) | `string` | `null` | no |
| vpc_id | VPC for the instances | `string` | n/a | yes |
| subnet_ids | Subnets for the Auto Scaling Group | `list(string)` | n/a | yes |
| public_ip_assignment_enabled | Assign public IPs to instances | `bool` | `false` | no |
| additional_security_group_ids | Extra security groups on the instances | `list(string)` | `[]` | no |
| direct_access_cidr_blocks | IPv4 CIDRs allowed to reach the app port directly | `list(string)` | `[]` | no |
| runtime | `container` or `manual` | `string` | n/a | yes |
| docker_socket_mount_enabled | Mount the host Docker socket and add the host `docker` group GID (container mode only; grants root-equivalent control of the instance) | `bool` | `false` | no |
| app_port | Port the app listens on | `number` | `null` | no |
| container_start_command | Optional container start command overriding the image CMD | `string` | `null` | no |
| manual_start_command | Long-running foreground manual app command managed by supervisord | `string` | `null` | yes for manual |
| environment_variables | Plain env vars written to the app env file | `list(object)` | `[]` | no |
| secrets | Secret env vars fetched on-instance from Secrets Manager / SSM Parameter Store (`{name, value_from}`) | `list(object)` | `[]` | no |
| deploy_health_check_path | Local HTTP path gating deploy success | `string` | `null` | no |
| deploy_timeout_seconds | Per-instance deploy script timeout | `number` | `1200` | no |
| instance_type | EC2 instance type; use the newest generation the region offers (see "Choosing an instance type") | `string` | n/a | yes |
| ami_id | Custom AMI (null = latest AL2023) | `string` | `null` | no |
| key_name | SSH key pair name | `string` | `null` | no |
| root_volume_size | Root EBS volume size (GB) | `number` | `30` | no |
| root_volume_type | Root EBS volume type | `string` | `"gp3"` | no |
| data_volume_creation_enabled | Attach a formatted per-instance data volume | `bool` | `false` | no |
| data_volume_size | Data volume size (GB) | `number` | `20` | no |
| data_volume_type | Data volume type | `string` | `"gp3"` | no |
| data_volume_mount_path | Host mount path for the data volume | `string` | `"/data"` | no |
| data_volume_snapshot_id | Snapshot used to restore a replacement data volume | `string` | `null` | no |
| additional_user_data | Extra shell script appended to bootstrap | `string` | `""` | no |
| min_size | Minimum instances | `number` | `1` | no |
| max_size | Maximum instances | `number` | `3` | no |
| desired_capacity | Desired instances (null = group-managed) | `number` | `null` | no |
| health_check_type | ASG health check: `EC2` or `ELB` | `string` | `"EC2"` | no |
| health_check_grace_period | Seconds before ASG health checks apply | `number` | `300` | no |
| cpu_autoscaling_enabled | Scale on average CPU utilization | `bool` | `false` | no |
| cpu_target_value | CPU utilization target (%) | `number` | `70` | no |
| load_balancer_attachment | Target group + listener rules (null = worker mode) | `object` | `null` | no |
| load_balancer_security_group_id | ALB security group allowed to reach the app port | `string` | `null` | no |
| efs_enabled | Mount an EFS file system on every instance | `bool` | `false` | no |
| efs_file_system_id | EFS file system ID | `string` | `null` | no |
| efs_access_point_id | EFS access point to mount through | `string` | `null` | no |
| efs_client_security_group_id | EFS client security group attached to instances | `string` | `null` | no |
| efs_mount_path | Host mount path for EFS | `string` | `"/mnt/efs"` | no |
| ecr_repository_creation_enabled | Create an ECR repository for built images | `bool` | `false` | no |
| ecr_force_deletion_enabled | Delete the ECR repository even with images | `bool` | `false` | no |
| ecr_scan_on_push_enabled | Scan images for vulnerabilities after push | `bool` | `true` | no |
| log_retention_in_days | CloudWatch app log retention | `number` | `30` | no |
| log_rotation_max_size_mb | Size at which supervisord rotates the on-instance app log | `number` | `20` | no |
| log_rotation_backup_count | Rotated app log files kept on the instance | `number` | `5` | no |
| backup_enabled | Schedule DLM EBS snapshots | `bool` | `false` | no |
| backup_interval_hours | Hours between snapshots (1, 2, 3, 4, 6, 8, 12, or 24) | `number` | `24` | no |
| backup_start_time | Snapshot schedule start time in UTC (HH:MM) | `string` | `"05:00"` | no |
| backup_retention_count | Snapshots retained | `number` | `7` | no |
| backup_root_volume_included | Include the root volume | `bool` | `false` | no |
| backup_consistency_mode | `crash_consistent`, `filesystem_freeze`, or `custom` | `string` | automatic | no |
| backup_pre_script_command | Custom pre-snapshot command | `string` | `null` | no |
| backup_post_script_command | Custom post-snapshot command | `string` | `null` | no |
| backup_cross_region_copy_destination | Destination AWS region for an additional copy | `string` | `null` | no |
| backup_dump_enabled | Schedule engine-native logical dumps | `bool` | `false` | no |
| backup_dump_command | Root dump command writing to `RAVION_BACKUP_DIR` | `string` | `null` | no |
| backup_dump_restore_command | Root restore command reading `RAVION_BACKUP_DIR` | `string` | `null` | no |
| backup_dump_schedule | systemd OnCalendar expression | `string` | `"*-*-* 04:00:00 UTC"` | no |
| backup_dump_destination | `s3` or `efs` logical dump destination | `string` | `"s3"` | no |
| backup_dump_s3_bucket_arn | Existing S3 bucket ARN, or null for a module-created bucket | `string` | `null` | no |
| backup_dump_s3_prefix | Prefix for logical dump artifacts | `string` | `"backups/"` | no |
| backup_dump_retention_days | Logical dump retention in days | `number` | `30` | no |
| backup_dump_max_interval_hours | Maximum expected interval between successful dumps; set higher than the schedule interval | `number` | `48` | no |
| backup_dump_force_deletion_enabled | Allow deletion of a non-empty module-created backup bucket | `bool` | `false` | no |
| backup_dump_restore_on_first_boot_enabled | Restore latest dump before first application start | `bool` | `false` | no |
| backup_max_age_hours | Maximum accepted restore age | `number` | `null` | no |
| backup_on_termination_enabled | Run a dump before planned ASG termination | `bool` | `true` | no |
| backup_dump_failure_alarm_enabled | Alarm on missing recent dump success | `bool` | `true` | no |
| backup_replication_enabled | Continuously replicate a SQLite database with Litestream | `bool` | `false` | no |
| backup_replication_engine | Continuous replication engine | `string` | `"litestream"` | no |
| backup_replication_database_path | SQLite database path under the data volume | `string` | `null` | no |
| backup_replication_s3_bucket_arn | Existing S3 bucket ARN, or null for a module-created bucket | `string` | `null` | no |
| backup_replication_restore_on_first_boot_enabled | Restore a replica before the first application start | `bool` | `false` | no |
| backup_replication_snapshot_interval | Litestream full snapshot interval | `string` | `"1m"` | no |
| backup_replication_retention | Litestream snapshot retention duration; must exceed the snapshot interval | `string` | `"24h"` | no |
| backup_replication_max_age_hours | Maximum accepted replica age on restore | `number` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| autoscaling_group_name | Name of the Auto Scaling Group deploys target |
| autoscaling_group_arn | ARN of the Auto Scaling Group |
| ssm_document_name | Name of the SSM deploy document |
| ssm_document_arn | ARN of the SSM deploy document |
| ecr_repository_arn | ARN of the service ECR repository (when created) |
| ecr_repository_url | URL of the service ECR repository (when created) |
| target_group_arn | ARN of the service target group (when attached) |
| target_group_arn_suffix | Target group ARN suffix for CloudWatch dimensions |
| security_group_id | ID of the instance security group |
| instance_role_arn | ARN of the instance IAM role |
| log_group_name | CloudWatch log group receiving app logs |
| log_stream_prefix | Prefix of deployment- and instance-scoped app log streams |
| aws_account_id | AWS account ID |
| region | AWS region |
| backup_policy_id | DLM policy ID when backups are enabled |
| backup_target_tag | Tag targeted by the DLM policy |
| backup_snapshot_filter | Tag filter for finding snapshots |
| backup_ssm_document_name | Consistency SSM document when scripts are enabled |
| backup_dump_bucket_name | Effective S3 logical dump bucket name |
| backup_dump_bucket_arn | Effective S3 logical dump bucket ARN |
| backup_dump_prefix | Service logical dump prefix |
| backup_dump_ssm_document_name | SSM command document for backup-now and restore-latest |
| backup_dump_termination_document_name | SSM Automation document for termination-time dumps |
| backup_replication_bucket_name | Effective S3 bucket name for Litestream replicas |
| backup_replication_bucket_arn | Effective S3 bucket ARN for Litestream replicas |
| backup_replication_prefix | Service Litestream replica prefix |
