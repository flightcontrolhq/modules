################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "The name of the IAM role. Mutually exclusive with name_prefix."
  default     = null

  validation {
    condition     = var.name == null || (length(var.name) >= 1 && length(var.name) <= 64)
    error_message = "The name must be between 1 and 64 characters."
  }
}

variable "name_prefix" {
  type        = string
  description = "Creates a unique name beginning with the specified prefix. Mutually exclusive with name."
  default     = null

  validation {
    condition     = var.name_prefix == null || length(var.name_prefix) <= 32
    error_message = "The name_prefix must be at most 32 characters."
  }
}

variable "description" {
  type        = string
  description = "The description of the IAM role."
  default     = "Managed by Terraform"
}

variable "path" {
  type        = string
  description = "The path to the IAM role."
  default     = "/"

  validation {
    condition     = can(regex("^/.*/$", var.path)) || var.path == "/"
    error_message = "The path must start and end with '/'."
  }
}

variable "max_session_duration" {
  type        = number
  description = "The maximum session duration (in seconds) for the IAM role."
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "The max_session_duration must be between 3600 and 43200 seconds."
  }
}

variable "force_detach_policies" {
  type        = bool
  description = "Whether to force detaching any policies the role has before destroying it."
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to all resources."
  default     = {}
}

################################################################################
# Assume Role Policy - Trusted Services
################################################################################

variable "trusted_services" {
  type        = list(string)
  description = <<-EOT
    List of AWS service principals that can assume this role.
    Examples: ["ecs-tasks.amazonaws.com", "lambda.amazonaws.com", "ec2.amazonaws.com"]
  EOT
  default     = []

  validation {
    condition = alltrue([
      for s in var.trusted_services : can(regex("\\.(amazonaws\\.com|amazonaws\\.com\\.cn)$", s))
    ])
    error_message = "All trusted_services must end with '.amazonaws.com' or '.amazonaws.com.cn'."
  }
}

################################################################################
# Assume Role Policy - Trusted AWS Principals
################################################################################

variable "trusted_aws_principals" {
  type        = list(string)
  description = <<-EOT
    List of AWS account IDs or ARNs that can assume this role.
    Examples: ["123456789012", "arn:aws:iam::123456789012:root", "arn:aws:iam::123456789012:role/MyRole"]
  EOT
  default     = []

  validation {
    condition = alltrue([
      for p in var.trusted_aws_principals : (
        can(regex("^\\d{12}$", p)) ||
        can(regex("^arn:aws(-cn|-us-gov)?:iam::", p))
      )
    ])
    error_message = "All trusted_aws_principals must be 12-digit account IDs or valid IAM ARNs."
  }
}

################################################################################
# Assume Role Policy - OIDC Providers
################################################################################

variable "trusted_oidc_providers" {
  type = list(object({
    provider_arn = string
    conditions = list(object({
      test     = string
      variable = string
      values   = list(string)
    }))
  }))
  description = <<-EOT
    List of OIDC identity providers that can assume this role.
    
    Example for GitHub Actions:
    ```
    trusted_oidc_providers = [{
      provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
      conditions = [{
        test     = "StringEquals"
        variable = "token.actions.githubusercontent.com:sub"
        values   = ["repo:org/repo:ref:refs/heads/main"]
      }]
    }]
    ```
    
    Example for EKS:
    ```
    trusted_oidc_providers = [{
      provider_arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE"
      conditions = [{
        test     = "StringEquals"
        variable = "oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE:sub"
        values   = ["system:serviceaccount:default:my-service-account"]
      }]
    }]
    ```
  EOT
  default     = []

  validation {
    condition = alltrue([
      for p in var.trusted_oidc_providers : can(regex("^arn:aws(-cn|-us-gov)?:iam::\\d{12}:oidc-provider/", p.provider_arn))
    ])
    error_message = "All trusted_oidc_providers provider_arn values must be valid OIDC provider ARNs."
  }
}

################################################################################
# Assume Role Policy - SAML Providers
################################################################################

variable "trusted_saml_providers" {
  type        = list(string)
  description = <<-EOT
    List of SAML provider ARNs that can assume this role.
    Example: ["arn:aws:iam::123456789012:saml-provider/MySAMLProvider"]
  EOT
  default     = []

  validation {
    condition = alltrue([
      for p in var.trusted_saml_providers : can(regex("^arn:aws(-cn|-us-gov)?:iam::\\d{12}:saml-provider/", p))
    ])
    error_message = "All trusted_saml_providers must be valid SAML provider ARNs."
  }
}

################################################################################
# Assume Role Policy - Conditions
################################################################################

variable "assume_role_conditions" {
  type = list(object({
    test     = string
    variable = string
    values   = list(string)
  }))
  description = <<-EOT
    Additional conditions to apply to all trust policy statements.
    Example for MFA requirement:
    ```
    assume_role_conditions = [{
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }]
    ```
  EOT
  default     = []
}

################################################################################
# Assume Role Policy - Custom
################################################################################

variable "custom_assume_role_policy" {
  type        = string
  description = <<-EOT
    A custom assume role policy JSON document. When provided, this overrides all other
    trust policy settings (trusted_services, trusted_aws_principals, trusted_oidc_providers,
    trusted_saml_providers, and assume_role_conditions).
  EOT
  default     = null
}

################################################################################
# Policy Attachments
################################################################################

variable "managed_policy_arns" {
  type        = list(string)
  description = <<-EOT
    List of managed policy ARNs to attach to the role.
    Examples: 
      - AWS managed: ["arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"]
      - Customer managed: ["arn:aws:iam::123456789012:policy/MyCustomPolicy"]
  EOT
  default     = []

  validation {
    condition = alltrue([
      for arn in var.managed_policy_arns : can(regex("^arn:aws(-cn|-us-gov)?:iam::(aws|\\d{12}):policy/", arn))
    ])
    error_message = "All managed_policy_arns must be valid IAM policy ARNs."
  }
}

################################################################################
# Inline Policies
################################################################################

variable "inline_policies" {
  type        = map(string)
  description = <<-EOT
    Map of inline policy names to JSON policy documents.
    Example:
    ```
    inline_policies = {
      "s3-access" = jsonencode({
        Version = "2012-10-17"
        Statement = [{
          Effect   = "Allow"
          Action   = ["s3:GetObject"]
          Resource = ["arn:aws:s3:::my-bucket/*"]
        }]
      })
    }
    ```
  EOT
  default     = {}
}

variable "inline_policy_statements" {
  type = list(object({
    sid       = optional(string)
    effect    = optional(string, "Allow")
    actions   = list(string)
    resources = list(string)
    conditions = optional(list(object({
      test     = string
      variable = string
      values   = list(string)
    })), [])
  }))
  description = <<-EOT
    List of inline policy statements to combine into a single policy.
    Example:
    ```
    inline_policy_statements = [
      {
        sid       = "AllowS3Read"
        actions   = ["s3:GetObject", "s3:ListBucket"]
        resources = ["arn:aws:s3:::my-bucket", "arn:aws:s3:::my-bucket/*"]
      },
      {
        sid       = "AllowCloudWatchLogs"
        actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        resources = ["*"]
      }
    ]
    ```
  EOT
  default     = []

  validation {
    condition = alltrue([
      for stmt in var.inline_policy_statements : contains(["Allow", "Deny"], stmt.effect)
    ])
    error_message = "All inline_policy_statements effect values must be 'Allow' or 'Deny'."
  }
}

################################################################################
# Permission Boundary
################################################################################

variable "permission_boundary_arn" {
  type        = string
  description = "The ARN of the policy that is used to set the permissions boundary for the role."
  default     = null

  validation {
    condition     = var.permission_boundary_arn == null || can(regex("^arn:aws(-cn|-us-gov)?:iam::(aws|\\d{12}):policy/", var.permission_boundary_arn))
    error_message = "The permission_boundary_arn must be a valid IAM policy ARN."
  }
}

################################################################################
# Instance Profile
################################################################################

variable "create_instance_profile" {
  type        = bool
  description = "Whether to create an IAM instance profile for this role."
  default     = false
}

variable "instance_profile_name" {
  type        = string
  description = "The name of the instance profile. Defaults to the role name if not specified."
  default     = null
}

variable "instance_profile_path" {
  type        = string
  description = "The path to the instance profile. Defaults to the role path if not specified."
  default     = null

  validation {
    condition     = var.instance_profile_path == null || can(regex("^/.*/$", var.instance_profile_path)) || var.instance_profile_path == "/"
    error_message = "The instance_profile_path must start and end with '/'."
  }
}
