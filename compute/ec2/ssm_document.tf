################################################################################
# Deploy SSM Document
#
# The aws:ec2 deploy contract. The deploy manager runs this document
# against the group's instances (batched, with per-instance status). The
# same document is run on scale-out instances to catch them up to the
# current release.
#
# Container runtime: the document takes imageUri (the full image URI to
# run) and encodes the whole in-place deploy.
#
# Manual runtime: the document takes commands (the service's deploy
# command list). Before running them it rebuilds the app env file
# (plain values and secrets) and exports it into the commands'
# environment, so deploys always see current configuration.
#
# NAMING CONTRACT: the document name is derived by the platform as
# "<autoscaling_group_name>-deploy" — both names come from var.name in
# this module, so the convention holds by construction. Do not rename
# one without the other (and the platform's Ec2DeployDocumentName).
################################################################################

resource "aws_ssm_document" "deploy" {
  name            = "${var.name}-deploy"
  document_type   = "Command"
  document_format = "YAML"

  content = local.container_runtime ? yamlencode({
    schemaVersion = "2.2"
    description   = "In-place container deploy for the ${var.name} EC2 service."

    parameters = {
      imageUri = {
        type           = "String"
        description    = "Full container image URI to deploy, including tag or digest."
        allowedPattern = "^[^\\s]+$"
      }
      deployId = {
        type           = "String"
        description    = "Identifier for this deploy, used for release directories and logging."
        default        = ""
        allowedPattern = "^[A-Za-z0-9._-]*$"
      }
    }

    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "deploy"
        inputs = {
          timeoutSeconds = tostring(var.deploy_timeout_seconds)
          runCommand     = [local.deploy_script]
        }
      }
    ]
    }) : yamlencode({
    schemaVersion = "2.2"
    description   = "Manual deploy for the ${var.name} EC2 service: refreshes and loads the app env file, then runs the service's deploy commands."

    parameters = {
      commands = {
        type        = "StringList"
        description = "Deploy commands to run on the instance, in order, with the app env file loaded."
      }
      deployId = {
        type           = "String"
        description    = "Identifier for this deploy, used for logging."
        default        = ""
        allowedPattern = "^[A-Za-z0-9._-]*$"
      }
    }

    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "deploy"
        inputs = {
          timeoutSeconds = tostring(var.deploy_timeout_seconds)
          runCommand = concat(
            [local.manual_deploy_prelude],
            ["{{ commands }}"],
          )
        }
      }
    ]
  })

  tags = local.tags
}
