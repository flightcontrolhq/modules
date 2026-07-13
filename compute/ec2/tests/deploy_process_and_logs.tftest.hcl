mock_provider "aws" {
  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }

  override_data {
    target = data.aws_region.current
    values = {
      id   = "us-east-1"
      name = "us-east-1"
    }
  }

  override_data {
    target = data.aws_partition.current
    values = {
      partition = "aws"
    }
  }

  override_resource {
    target = aws_iam_instance_profile.instance
    values = {
      arn = "arn:aws:iam::123456789012:instance-profile/supervised-app-instance"
    }
  }

  override_resource {
    target = module.instance_security_group.aws_security_group.this
    values = {
      id = "sg-12345678"
    }
  }

  override_resource {
    target = aws_launch_template.app
    values = {
      id = "lt-12345678"
    }
  }
}

variables {
  name          = "supervised-app"
  region        = "us-east-1"
  vpc_id        = "vpc-12345678"
  subnet_ids    = ["subnet-12345678"]
  instance_type = "t3.micro"
  ami_id        = "ami-12345678"
}

run "container_is_supervised_and_logs_per_deployment" {
  command = plan

  variables {
    runtime = "container"
  }

  assert {
    condition     = strcontains(aws_ssm_document.deploy.content, "autorestart=true")
    error_message = "Container deploys must configure supervisord to restart the app."
  }

  assert {
    condition     = strcontains(aws_ssm_document.deploy.content, "deployment/$${DEPLOY_ID}/instance/{instance_id}")
    error_message = "Container logs must use deployment- and instance-scoped CloudWatch streams."
  }

  assert {
    condition     = strcontains(base64decode(aws_launch_template.app.user_data), "supervisor==4.3.0")
    error_message = "Instances must install the pinned Supervisor version at bootstrap."
  }

  assert {
    condition     = output.log_stream_prefix == "deployment"
    error_message = "The log stream output must select all deployment-scoped streams."
  }

}

run "manual_start_command_is_supervised" {
  command = plan

  variables {
    runtime              = "manual"
    manual_start_command = "cd /srv/app && ./bin/server"
  }

  assert {
    condition     = strcontains(aws_ssm_document.deploy.content, base64encode("cd /srv/app && ./bin/server"))
    error_message = "The manual start command must be embedded safely in the deploy document."
  }

  assert {
    condition     = strcontains(aws_ssm_document.deploy.content, "exec /bin/bash -lc")
    error_message = "Manual deploys must run the long-lived start command through the supervisor runner."
  }

  assert {
    condition     = strcontains(aws_ssm_document.deploy.content, "autorestart=true")
    error_message = "Manual deploys must configure supervisord to restart the app."
  }

  assert {
    condition     = strcontains(aws_ssm_document.deploy.content, "sourceRepo") && strcontains(aws_ssm_document.deploy.content, "gitTokenParameterName")
    error_message = "Manual deploys must expose the optional nested source transport parameters."
  }

  assert {
    condition     = strcontains(base64decode(aws_launch_template.app.user_data), "dnf install -y git jq unzip")
    error_message = "Instances must install Git at bootstrap for source-backed manual deploys."
  }

  assert {
    condition     = strcontains(aws_ssm_document.deploy.content, "GIT_ASKPASS") && strcontains(aws_ssm_document.deploy.content, "SOURCE_DIRECTORY=\"$SOURCE_ROOT/source\"")
    error_message = "Manual deploys must authenticate transiently and check source out under the Ravion-managed directory."
  }

  assert {
    condition     = strcontains(aws_ssm_document.deploy.content, "if ! command -v git") && strcontains(aws_ssm_document.deploy.content, "dnf install -y git")
    error_message = "Source-backed manual deploys must install Git on existing instances before checkout."
  }

  assert {
    condition     = strcontains(aws_ssm_document.deploy.content, "source-working-directory")
    error_message = "Manual deploy and start commands must share the selected source working directory."
  }

  assert {
    condition     = yamldecode(aws_ssm_document.deploy.content).parameters.commands.type == "String"
    error_message = "Manual deploy commands must use a String parameter so the command script can be embedded between the prelude and postlude."
  }

  assert {
    condition     = length(yamldecode(aws_ssm_document.deploy.content).mainSteps[0].inputs.runCommand) == 1 && strcontains(yamldecode(aws_ssm_document.deploy.content).mainSteps[0].inputs.runCommand[0], "{{ commands }}")
    error_message = "Manual deploy setup, commands, and teardown must be one runCommand string so SSM does not create a nested command array during parameter substitution."
  }
}
