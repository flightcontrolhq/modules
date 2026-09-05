mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-2" }
  }
  mock_data "aws_eks_cluster" {
    defaults = {
      arn                   = "arn:aws:eks:us-east-2:123456789012:cluster/test-cluster"
      endpoint              = "https://mock.eks.amazonaws.com"
      certificate_authority = [{ data = "bW9jay1jYQ==" }]
      vpc_config = [{
        vpc_id                    = "vpc-12345678"
        cluster_security_group_id = "sg-12345678"
        control_plane_egress_mode = ""
        endpoint_private_access   = true
        endpoint_public_access    = false
        public_access_cidrs       = []
        security_group_ids        = []
        subnet_ids                = []
      }]
    }
  }
}
mock_provider "helm" {}
mock_provider "ravion" {}

variables {
  cluster_name                      = "test-cluster"
  region                            = "us-east-2"
  karpenter_enabled                 = false
  eso_enabled                       = false
  logs_providers                    = []
  metrics_providers                 = []
  ravion_operator_enabled           = true
  ravion_operator_deploy_enabled    = true
  ravion_operator_deploy_namespaces = ["rvn-app", "rvn-app"]
}

run "bootstrap_deployment_namespaces" {
  command = plan
  assert {
    condition     = yamldecode(helm_release.ravion_operator_namespaces[0].values[0]).namespaces == ["rvn-app"]
    error_message = "Apply must bootstrap the configured deployment namespace once."
  }
  assert {
    condition     = helm_release.ravion_operator_namespaces[0].namespace == "kube-system"
    error_message = "Namespace bootstrap must not move when the Operator namespace changes."
  }
  assert {
    condition     = helm_release.ravion_operator[0].namespace == "ravion-operator" && helm_release.ravion_operator_credential[0].namespace == "ravion-operator"
    error_message = "The agent and its credential must share the new default namespace."
  }
}

run "bootstrap_observation_and_deployment_namespaces" {
  command = plan
  variables {
    ravion_operator_namespace_scope = ["observed", "rvn-app"]
  }
  assert {
    condition     = yamldecode(helm_release.ravion_operator_namespaces[0].values[0]).namespaces == ["observed", "rvn-app"]
    error_message = "Both observation and deployment RBAC require existing namespaces."
  }
}

run "deployment_scope_fallback" {
  command = plan
  variables {
    ravion_operator_deploy_namespaces = []
    ravion_operator_namespace_scope   = ["observed"]
  }
  assert {
    condition     = yamldecode(helm_release.ravion_operator_namespaces[0].values[0]).namespaces == ["observed"]
    error_message = "Bootstrap must follow the chart's observation-scope fallback."
  }
}

run "no_deployment_namespaces_when_deploy_disabled" {
  command = plan
  variables {
    ravion_operator_deploy_enabled = false
  }
  assert {
    condition     = length(helm_release.ravion_operator_namespaces) == 0
    error_message = "Unused deployment namespaces must not be created."
  }
}

run "externally_provisioned_namespaces" {
  command = plan
  variables {
    ravion_operator_namespaces_creation_enabled = false
    ravion_operator_namespace                   = "existing-agent"
  }
  assert {
    condition     = length(helm_release.ravion_operator_namespaces) == 0 && helm_release.ravion_operator[0].namespace == "existing-agent"
    error_message = "External namespace management and explicit agent namespace overrides must remain supported."
  }
}

run "operator_disabled" {
  command = plan
  variables {
    ravion_operator_enabled = false
  }
  assert {
    condition     = length(helm_release.ravion_operator_namespaces) == 0
    error_message = "Disabling Operator must skip namespace bootstrap."
  }
}

run "invalid_namespace_rejected" {
  command = plan
  variables {
    ravion_operator_deploy_namespaces = ["Invalid_Namespace"]
  }
  expect_failures = [var.ravion_operator_deploy_namespaces]
}
