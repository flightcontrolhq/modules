resource "aws_ssm_document" "backup" {
  count           = local.backup_scripts_enabled ? 1 : 0
  name            = "${var.name}-backup-consistency"
  document_type   = "Command"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "2.2"
    description   = "DLM EBS snapshot consistency hooks for the ${var.name} service."
    parameters = {
      command = {
        type          = "String"
        allowedValues = ["pre-script", "post-script", "dry-run"]
      }
      executionId = {
        type = "String"
      }
    }
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "backupConsistency"
      inputs = {
        timeoutSeconds = "1200"
        runCommand = [join("\n", [
          "set -euo pipefail",
          "MOUNT_PATH=$(printf '%s' '${var.data_volume_mount_path}')",
          "THAW_UNIT=ravion-${var.name}-backup-thaw",
          "thaw() { systemctl stop \"$THAW_UNIT\" 2>/dev/null || true; fsfreeze -u \"$MOUNT_PATH\" 2>/dev/null || true; }",
          "if [ '{{ command }}' = 'dry-run' ]; then exit 0; fi",
          "if [ '{{ command }}' = 'pre-script' ]; then",
          local.backup_consistency_mode == "filesystem_freeze" ? "  sync\n  fsfreeze -f \"$MOUNT_PATH\"\n  systemd-run --unit=\"$THAW_UNIT\" --collect /bin/sh -c \"sleep 900; fsfreeze -u '$MOUNT_PATH' 2>/dev/null || true\"" : "  ${local.backup_pre_script_command}",
          "elif [ '{{ command }}' = 'post-script' ]; then",
          local.backup_consistency_mode == "filesystem_freeze" ? "  thaw" : "  ${local.backup_post_script_command}",
          "fi",
        ])]
      }
    }]
  })

  tags = local.tags
}
