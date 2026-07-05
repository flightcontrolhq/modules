################################################################################
# Deploy SSM Document (container runtime only)
#
# The aws:ec2 container deploy contract. The deploy manager runs this
# document against the group's instances (batched, with per-instance
# status) and passes imageUri, the full image URI to run. The same
# document is run on scale-out instances to catch them up to the current
# release.
#
# NAMING CONTRACT: the document name is derived by the platform as
# "<autoscaling_group_name>-deploy" — both names come from var.name in
# this module, so the convention holds by construction. Do not rename
# one without the other (and the platform's Ec2DeployDocumentName).
#
# The manual runtime has no document: the deploy manager sends the
# service's deploy commands directly through AWS-RunShellScript.
################################################################################

resource "aws_ssm_document" "deploy" {
  count = local.container_runtime ? 1 : 0

  name            = "${var.name}-deploy"
  document_type   = "Command"
  document_format = "YAML"

  content = yamlencode({
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
  })

  tags = local.tags
}
