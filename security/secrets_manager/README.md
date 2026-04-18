# AWS Secrets Manager

Creates an AWS Secrets Manager secret and optionally an initial version and resource policy.

## Usage

```hcl
module "db_secret" {
  source = "git::https://github.com/user/ravion-modules.git//security/secrets_manager?ref=v1.0.0"

  name        = "myapp/db/connection-string"
  description = "Connection string for the app database"

  secret_string = "postgres://user:pass@host:5432/db"

  tags = {
    Environment = "production"
  }
}
```

### Storing a JSON object

```hcl
module "api_credentials" {
  source = "../../security/secrets_manager"

  name = "myapp/api"

  secret_json = {
    client_id     = "abc"
    client_secret = "xyz"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name of the Secrets Manager secret. | `string` | n/a | yes |
| description | Description for the secret. | `string` | `null` | no |
| tags | Tags to assign to the secret. | `map(string)` | `{}` | no |
| secret_string | The plaintext value to store. Mutually exclusive with `secret_json`. | `string` | `null` | no |
| secret_json | A map stored as JSON. Mutually exclusive with `secret_string`. | `any` | `null` | no |
| kms_key_id | KMS key ARN, ID, or alias used to encrypt the secret. | `string` | `null` | no |
| recovery_window_in_days | Recovery window in days (0 for immediate delete, else 7–30). | `number` | `7` | no |
| policy | JSON resource policy document to attach to the secret. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| arn | The ARN of the Secrets Manager secret. |
| id | The ID of the Secrets Manager secret (same as ARN). |
| name | The name of the Secrets Manager secret. |
| version_id | The unique identifier of the current secret version. |
