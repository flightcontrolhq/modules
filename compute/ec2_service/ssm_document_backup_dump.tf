################################################################################
# One-click logical dump and restore commands
################################################################################

resource "aws_ssm_document" "backup_dump" {
  count           = var.backup_dump_enabled ? 1 : 0
  name            = "${var.name}-backup"
  document_type   = "Command"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "2.2"
    description   = "Run or restore a logical backup for the ${var.name} EC2 service."
    parameters = {
      command = {
        type          = "String"
        allowedValues = ["backup-now", "restore-latest"]
      }
    }
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "backupDump"
      inputs = {
        timeoutSeconds = "3600"
        runCommand = [
          "echo '${base64encode(local.backup_dump_script)}' | base64 -d > /tmp/${var.name}-backup.sh",
          "chmod 700 /tmp/${var.name}-backup.sh",
          "bash /tmp/${var.name}-backup.sh '{{ command }}'",
        ]
      }
    }]
  })

  tags = local.tags
}
