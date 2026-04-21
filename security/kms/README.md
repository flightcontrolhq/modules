# AWS KMS Key Module

Provisions an AWS KMS Customer Master Key (CMK) plus a stable alias. Supports both **symmetric** (envelope-encryption) and **asymmetric** (signing, key agreement, MAC) shapes via `key_spec` / `key_usage`. The key policy adapts to the chosen shape: `signer_role_arns` translates to `kms:Sign` for `SIGN_VERIFY` keys and `kms:GenerateMac` for `GENERATE_VERIFY_MAC` keys, etc.

## Features

- Symmetric (`SYMMETRIC_DEFAULT`) keys for envelope encryption (default).
- Asymmetric `RSA_*`, `ECC_*`, `SM2` keys for signing or encryption.
- `HMAC_*` keys for `GENERATE_VERIFY_MAC`.
- Annual automatic rotation for symmetric keys (auto-disabled for shapes that don't support it).
- Per-action principal lists (`key_user_role_arns`, `signer_role_arns`, `public_key_reader_role_arns`, `key_administrator_role_arns`) — empty by default so the key can be provisioned before its consumers exist.
- A separate `public_key_reader_role_arns` list that grants `kms:GetPublicKey` / `kms:DescribeKey` but explicitly **not** `kms:Sign` — useful for JWKS-publisher style workloads that must be cryptographically prevented from forging signatures.
- Optional multi-region primary key (`multi_region = true`).

## Usage

### Symmetric envelope-encryption key (default)

```hcl
module "app_data_key" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//security/kms?ref=v1.0.0"

  name = "app-data"

  key_user_role_arns = [
    aws_iam_role.app.arn,
  ]

  tags = {
    Environment = "prod"
  }
}
```

### Asymmetric RSA signing key (e.g. OIDC JWT signer)

```hcl
module "oidc_signer" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//security/kms?ref=v1.0.0"

  name      = "oidc-signer-prod"
  key_spec  = "RSA_2048"
  key_usage = "SIGN_VERIFY"

  # Only the signing service may mint signatures.
  signer_role_arns = [
    aws_iam_role.signing_service.arn,
  ]

  # The publisher can read the public key but cannot forge signatures.
  public_key_reader_role_arns = [
    aws_iam_role.jwks_publisher.arn,
  ]
}
```

### HMAC key

```hcl
module "session_hmac" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//security/kms?ref=v1.0.0"

  name      = "session-hmac"
  key_spec  = "HMAC_256"
  key_usage = "GENERATE_VERIFY_MAC"

  signer_role_arns   = [aws_iam_role.session_signer.arn]
  key_user_role_arns = [aws_iam_role.session_verifier.arn]
}
```

### Bootstrap pattern (consumers don't yet exist)

All principal lists default to `[]`, so you can apply the key first and re-apply later once the consuming roles are created:

```hcl
module "kms" {
  source = "git::https://github.com/flightcontrolhq/ravion-modules.git//security/kms?ref=v1.0.0"

  name = "future-key"
  # Apply once with no role lists, then re-apply once the broker / publisher /
  # app role ARNs are known. Or plumb them through in one composition and
  # Terraform will resolve the dependency edge correctly.
}
```

## Requirements

| Name               | Version   |
| ------------------ | --------- |
| opentofu/terraform | >= 1.10.0 |
| aws                | >= 5.0    |

## Inputs

| Name                          | Description                                                                                                                                                                                                                                                                                                                                                  | Type           | Default               | Required |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------- | --------------------- | -------- |
| `name`                        | Short, human-readable name. Used as alias suffix (`alias/<name>`) and tag handle. 1–64 chars; alphanumerics, `/`, `_`, `-` only.                                                                                                                                                                                                                              | `string`       | n/a                   | yes      |
| `description`                 | Free-form key description. Defaults to `"KMS key for <name>."`.                                                                                                                                                                                                                                                                                              | `string`       | `null`                | no       |
| `alias`                       | Override for the alias suffix (without the `alias/` prefix). Defaults to `var.name`.                                                                                                                                                                                                                                                                         | `string`       | `null`                | no       |
| `key_spec`                    | `SYMMETRIC_DEFAULT`, `RSA_2048\|3072\|4096`, `ECC_NIST_P256\|P384\|P521`, `ECC_SECG_P256K1`, `HMAC_224\|256\|384\|512`, or `SM2`.                                                                                                                                                                                                                              | `string`       | `"SYMMETRIC_DEFAULT"` | no       |
| `key_usage`                   | One of `ENCRYPT_DECRYPT`, `SIGN_VERIFY`, `GENERATE_VERIFY_MAC`, `KEY_AGREEMENT`. Must be valid for the chosen `key_spec`.                                                                                                                                                                                                                                    | `string`       | `"ENCRYPT_DECRYPT"`   | no       |
| `multi_region`                | Create as a multi-region primary key.                                                                                                                                                                                                                                                                                                                        | `bool`         | `false`               | no       |
| `enable_key_rotation`         | Enable annual automatic rotation. AWS only supports rotation for `SYMMETRIC_DEFAULT` + `ENCRYPT_DECRYPT`; ignored for any other shape.                                                                                                                                                                                                                       | `bool`         | `true`                | no       |
| `deletion_window_in_days`     | Pending-delete window (7–30). Default is the maximum safety window.                                                                                                                                                                                                                                                                                          | `number`       | `30`                  | no       |
| `key_administrator_role_arns` | Principals granted administrative actions on the key (Describe / Get / List / Put / Update / Enable / Disable / Tag* / ScheduleKeyDeletion / etc). **Does not** grant cryptographic operations.                                                                                                                                                              | `list(string)` | `[]`                  | no       |
| `key_user_role_arns`          | Principals permitted to use the key for the cryptographic operations matching `key_usage` (e.g. Encrypt/Decrypt for `ENCRYPT_DECRYPT`, Verify/GetPublicKey for `SIGN_VERIFY`, VerifyMac for `GENERATE_VERIFY_MAC`, DeriveSharedSecret for `KEY_AGREEMENT`).                                                                                                  | `list(string)` | `[]`                  | no       |
| `signer_role_arns`            | Principals permitted to call `kms:Sign` (for `SIGN_VERIFY` keys) or `kms:GenerateMac` (for `GENERATE_VERIFY_MAC` keys). Granted alongside `kms:DescribeKey` and `kms:GetPublicKey` so signers can self-introspect. Ignored when `key_usage` does not support signing.                                                                                       | `list(string)` | `[]`                  | no       |
| `public_key_reader_role_arns` | Principals permitted to call `kms:GetPublicKey` and `kms:DescribeKey` only. Explicitly **does not** grant `kms:Sign` or `kms:Verify`, so a compromised reader cannot forge or validate signatures. Useful for JWKS-publisher style workloads.                                                                                                               | `list(string)` | `[]`                  | no       |
| `tags`                        | Extra tags applied to both the key and the alias.                                                                                                                                                                                                                                                                                                            | `map(string)`  | `{}`                  | no       |

## Outputs

| Name         | Description                                                                                              |
| ------------ | -------------------------------------------------------------------------------------------------------- |
| `key_id`     | The KMS key UUID.                                                                                        |
| `key_arn`    | The KMS key ARN. Use as `Resource` in IAM role policies that grant cryptographic operations on this key. |
| `alias_name` | The alias name (`alias/<name>`). Stable across rotations.                                                |
| `alias_arn`  | The alias ARN.                                                                                           |
| `key_spec`   | The key spec the key was created with.                                                                   |
| `key_usage`  | The key usage the key was created with.                                                                  |

## Tags applied by the module

Every resource receives:

- `ManagedBy = "terraform"`
- `Module = "security/kms"`
- Anything else supplied via `var.tags`

## Key policy shape

The key policy is built from up to five statements:

1. `EnableIAMUserPermissions` — always present. Grants `arn:aws:iam::<account>:root` full KMS access. Standard AWS KMS pattern; without it the key becomes unmanageable via IAM.
2. `AllowKeyAdministration` — present iff `key_administrator_role_arns` is non-empty. Administrative actions only, no cryptographic operations.
3. `AllowKeyUse` — present iff `key_user_role_arns` is non-empty. Actions match `key_usage`.
4. `AllowSign` — present iff `signer_role_arns` is non-empty **and** `key_usage` supports signing (`SIGN_VERIFY` or `GENERATE_VERIFY_MAC`).
5. `AllowPublicKeyRead` — present iff `public_key_reader_role_arns` is non-empty. Grants `kms:GetPublicKey` + `kms:DescribeKey` only.

## Rotation

- **Symmetric (`SYMMETRIC_DEFAULT`)**: AWS rotates the key material annually when `enable_key_rotation = true`. The alias and key ID stay constant.
- **Asymmetric (`RSA_*`, `ECC_*`, `SM2`) / `HMAC_*`**: AWS does not support automatic rotation. Use a manual rotation runbook: create a new key, dual-publish (e.g. publish both public keys in a JWKS document), switch signing/encryption to the new key, retire the old key after a soak period, then schedule deletion.

## CloudTrail

`kms:Sign`, `kms:Decrypt`, `kms:GenerateDataKey`, etc. are captured automatically as CloudTrail management events. No per-key CloudTrail configuration is required by this module; the org/account trail must exist and be enabled at the composition level.
