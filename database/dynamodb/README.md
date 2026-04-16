# AWS DynamoDB

Creates an Amazon DynamoDB table with support for on-demand and provisioned billing, global & local secondary indexes, streams, TTL, point-in-time recovery, server-side encryption (AWS or KMS), global table v2 replicas, application autoscaling, and CloudWatch alarms.

## Features

- **Flexible billing**: `PAY_PER_REQUEST` (on-demand) or `PROVISIONED`
- **Secondary indexes**: global (GSI) and local (LSI) with configurable projections
- **Streams**: DynamoDB Streams with all four view types
- **Global tables v2**: declarative multi-region replicas
- **TTL**: time-based item expiration
- **Encryption at rest**: on by default; optional customer-managed KMS key
- **Point-in-time recovery**: on by default (configurable)
- **Deletion protection**: optional
- **Autoscaling**: target-tracking autoscaling on table + per-GSI read/write capacity (provisioned only)
- **CloudWatch alarms**: optional throttling and system-error alarms

## Usage

### Basic (on-demand)

```hcl
module "dynamodb" {
  source = "git::https://github.com/flightcontrolhq/modules.git//database/dynamodb?ref=v1.0.0"

  name     = "my-app-sessions"
  hash_key = "session_id"

  attributes = [
    { name = "session_id", type = "S" },
  ]

  ttl_enabled        = true
  ttl_attribute_name = "expires_at"
}
```

### With GSI, LSI, and Streams

```hcl
module "dynamodb" {
  source = "git::https://github.com/flightcontrolhq/modules.git//database/dynamodb?ref=v1.0.0"

  name      = "my-app-events"
  hash_key  = "user_id"
  range_key = "created_at"

  attributes = [
    { name = "user_id", type = "S" },
    { name = "created_at", type = "N" },
    { name = "event_type", type = "S" },
  ]

  global_secondary_indexes = [
    {
      name            = "by_event_type"
      hash_key        = "event_type"
      range_key       = "created_at"
      projection_type = "ALL"
    },
  ]

  local_secondary_indexes = [
    {
      name            = "by_user_event_type"
      range_key       = "event_type"
      projection_type = "KEYS_ONLY"
    },
  ]

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"
}
```

### Provisioned with autoscaling

```hcl
module "dynamodb" {
  source = "git::https://github.com/flightcontrolhq/modules.git//database/dynamodb?ref=v1.0.0"

  name         = "my-app-orders"
  hash_key     = "order_id"
  billing_mode = "PROVISIONED"

  attributes     = [{ name = "order_id", type = "S" }]
  read_capacity  = 5
  write_capacity = 5

  autoscaling_enabled = true
  autoscaling_read    = { min_capacity = 5, max_capacity = 100 }
  autoscaling_write   = { min_capacity = 5, max_capacity = 100 }
}
```

> **Note**: When autoscaling is enabled the module ignores drift on `read_capacity` / `write_capacity` / `global_secondary_index` so Terraform does not fight Application Auto Scaling.

### Global table (multi-region replicas)

```hcl
module "dynamodb" {
  source = "git::https://github.com/flightcontrolhq/modules.git//database/dynamodb?ref=v1.0.0"

  name     = "my-app-global-users"
  hash_key = "user_id"

  attributes     = [{ name = "user_id", type = "S" }]
  stream_enabled = true # required for v2 replicas

  replicas = [
    { region_name = "us-west-2" },
    { region_name = "eu-west-1", point_in_time_recovery = true },
  ]
}
```

## Requirements

| Name               | Version   |
| ------------------ | --------- |
| opentofu/terraform | >= 1.10.0 |
| aws                | >= 5.0    |

## Inputs

| Name                                 | Description                                                                                     | Type                                                                                                                                                                                                                                                                                                                                                                                                  | Default                                  | Required |
| ------------------------------------ | ----------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------- | -------- |
| name                                 | Table name (also used as prefix for alarms / autoscaling policies).                             | `string`                                                                                                                                                                                                                                                                                                                                                                                              | n/a                                      | yes      |
| tags                                 | Tags to assign to all resources.                                                                | `map(string)`                                                                                                                                                                                                                                                                                                                                                                                         | `{}`                                     | no       |
| hash_key                             | Partition key attribute name.                                                                   | `string`                                                                                                                                                                                                                                                                                                                                                                                              | n/a                                      | yes      |
| range_key                            | Sort key attribute name.                                                                        | `string`                                                                                                                                                                                                                                                                                                                                                                                              | `null`                                   | no       |
| attributes                           | Attribute definitions. Type ∈ `S` `N` `B`.                                                      | `list(object({ name = string, type = string }))`                                                                                                                                                                                                                                                                                                                                                      | n/a                                      | yes      |
| billing_mode                         | `PAY_PER_REQUEST` or `PROVISIONED`.                                                             | `string`                                                                                                                                                                                                                                                                                                                                                                                              | `"PAY_PER_REQUEST"`                      | no       |
| read_capacity                        | RCUs. Required when provisioned.                                                                | `number`                                                                                                                                                                                                                                                                                                                                                                                              | `null`                                   | no       |
| write_capacity                       | WCUs. Required when provisioned.                                                                | `number`                                                                                                                                                                                                                                                                                                                                                                                              | `null`                                   | no       |
| table_class                          | `STANDARD` or `STANDARD_INFREQUENT_ACCESS`.                                                     | `string`                                                                                                                                                                                                                                                                                                                                                                                              | `"STANDARD"`                             | no       |
| global_secondary_indexes             | List of GSIs.                                                                                   | `list(object({ name = string, hash_key = string, range_key = optional(string), projection_type = string, non_key_attributes = optional(list(string)), read_capacity = optional(number), write_capacity = optional(number) }))`                                                                                                                                                                       | `[]`                                     | no       |
| local_secondary_indexes              | List of LSIs. Requires `range_key`.                                                             | `list(object({ name = string, range_key = string, projection_type = string, non_key_attributes = optional(list(string)) }))`                                                                                                                                                                                                                                                                         | `[]`                                     | no       |
| ttl_enabled                          | Enable TTL.                                                                                     | `bool`                                                                                                                                                                                                                                                                                                                                                                                                | `false`                                  | no       |
| ttl_attribute_name                   | Attribute used for TTL.                                                                         | `string`                                                                                                                                                                                                                                                                                                                                                                                              | `""`                                     | no       |
| stream_enabled                       | Enable DynamoDB Streams.                                                                        | `bool`                                                                                                                                                                                                                                                                                                                                                                                                | `false`                                  | no       |
| stream_view_type                     | `KEYS_ONLY`, `NEW_IMAGE`, `OLD_IMAGE`, `NEW_AND_OLD_IMAGES`.                                    | `string`                                                                                                                                                                                                                                                                                                                                                                                              | `"NEW_AND_OLD_IMAGES"`                   | no       |
| server_side_encryption_enabled       | Enable SSE at rest.                                                                             | `bool`                                                                                                                                                                                                                                                                                                                                                                                                | `true`                                   | no       |
| server_side_encryption_kms_key_arn   | Customer-managed KMS key ARN. Null uses AWS-owned key.                                          | `string`                                                                                                                                                                                                                                                                                                                                                                                              | `null`                                   | no       |
| point_in_time_recovery_enabled       | Enable PITR.                                                                                    | `bool`                                                                                                                                                                                                                                                                                                                                                                                                | `true`                                   | no       |
| deletion_protection_enabled          | Prevent accidental deletion.                                                                    | `bool`                                                                                                                                                                                                                                                                                                                                                                                                | `false`                                  | no       |
| replicas                             | Global table v2 replica regions. Requires `stream_enabled = true`.                              | `list(object({ region_name = string, kms_key_arn = optional(string), propagate_tags = optional(bool), point_in_time_recovery = optional(bool) }))`                                                                                                                                                                                                                                                   | `[]`                                     | no       |
| autoscaling_enabled                  | Enable autoscaling on table capacity (provisioned only).                                        | `bool`                                                                                                                                                                                                                                                                                                                                                                                                | `false`                                  | no       |
| autoscaling_read                     | Read-capacity autoscaling config.                                                               | `object({ min_capacity = number, max_capacity = number, target_utilization = optional(number), scale_in_cooldown = optional(number), scale_out_cooldown = optional(number) })`                                                                                                                                                                                                                        | `{ min_capacity = 5, max_capacity = 100 }` | no       |
| autoscaling_write                    | Write-capacity autoscaling config.                                                              | `object({...})`                                                                                                                                                                                                                                                                                                                                                                                       | `{ min_capacity = 5, max_capacity = 100 }` | no       |
| autoscaling_indexes                  | Per-GSI autoscaling config, keyed by GSI name.                                                  | `map(object({ read = optional(object({...})), write = optional(object({...})) }))`                                                                                                                                                                                                                                                                                                                    | `{}`                                     | no       |
| create_cloudwatch_alarms             | Create throttling & system-error alarms.                                                        | `bool`                                                                                                                                                                                                                                                                                                                                                                                                | `false`                                  | no       |
| cloudwatch_alarm_actions             | ARNs notified on ALARM.                                                                         | `list(string)`                                                                                                                                                                                                                                                                                                                                                                                        | `[]`                                     | no       |
| cloudwatch_ok_actions                | ARNs notified on OK.                                                                            | `list(string)`                                                                                                                                                                                                                                                                                                                                                                                        | `[]`                                     | no       |
| cloudwatch_alarm_evaluation_periods  | Evaluation periods for each alarm.                                                              | `number`                                                                                                                                                                                                                                                                                                                                                                                              | `2`                                      | no       |
| cloudwatch_alarm_period              | Statistic period (seconds).                                                                     | `number`                                                                                                                                                                                                                                                                                                                                                                                              | `300`                                    | no       |
| cloudwatch_read_throttle_threshold   | `ReadThrottleEvents` alarm threshold.                                                           | `number`                                                                                                                                                                                                                                                                                                                                                                                              | `10`                                     | no       |
| cloudwatch_write_throttle_threshold  | `WriteThrottleEvents` alarm threshold.                                                          | `number`                                                                                                                                                                                                                                                                                                                                                                                              | `10`                                     | no       |
| cloudwatch_system_errors_threshold   | `SystemErrors` alarm threshold.                                                                 | `number`                                                                                                                                                                                                                                                                                                                                                                                              | `5`                                      | no       |
| timeouts                             | Override create/update/delete timeouts.                                                         | `object({ create = optional(string), update = optional(string), delete = optional(string) })`                                                                                                                                                                                                                                                                                                         | `{}`                                     | no       |

## Outputs

| Name                                | Description                                                  |
| ----------------------------------- | ------------------------------------------------------------ |
| table_id                            | ID (name) of the DynamoDB table.                             |
| table_name                          | Name of the DynamoDB table.                                  |
| table_arn                           | ARN of the DynamoDB table.                                   |
| table_hash_key                      | Hash (partition) key.                                        |
| table_range_key                     | Range (sort) key, if any.                                    |
| billing_mode                        | Effective billing mode.                                      |
| table_class                         | Storage class.                                               |
| stream_arn                          | DynamoDB Stream ARN (null when disabled).                    |
| stream_label                        | DynamoDB Stream label (null when disabled).                  |
| global_secondary_index_names        | Names of configured GSIs.                                    |
| local_secondary_index_names         | Names of configured LSIs.                                    |
| autoscaling_table_read_target_arn   | Read autoscaling target ARN (null when disabled).            |
| autoscaling_table_write_target_arn  | Write autoscaling target ARN (null when disabled).           |
| autoscaling_gsi_target_arns         | Map of GSI autoscaling target ARNs.                          |
| cloudwatch_alarm_arns               | Map of CloudWatch alarm ARNs.                                |
| replica_regions                     | Regions where the global table is replicated.                |
| region                              | AWS region where the table is created.                       |
