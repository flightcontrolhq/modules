################################################################################
# Cross-Variable Validation
################################################################################

check "role_configuration" {
  assert {
    condition = (
      var.create_role ||
      var.role_arn != null
    )
    error_message = "When create_role is false, role_arn must be provided."
  }
}

check "zip_package_configuration" {
  assert {
    condition = (
      var.package_type != "Zip" ||
      (
        var.handler != null &&
        var.runtime != null &&
        (
          var.filename != null ||
          (var.s3_bucket != null && var.s3_key != null)
        ) &&
        var.image_uri == null
      )
    )
    error_message = "For package_type 'Zip', set handler/runtime and either filename or (s3_bucket + s3_key), and do not set image_uri."
  }
}

check "image_package_configuration" {
  assert {
    condition = (
      var.package_type != "Image" ||
      (
        var.image_uri != null &&
        var.filename == null &&
        var.s3_bucket == null &&
        var.s3_key == null &&
        var.s3_object_version == null
      )
    )
    error_message = "For package_type 'Image', set image_uri and do not set filename/s3_* values."
  }
}

check "lambda_at_edge_constraints" {
  assert {
    condition = (
      !var.is_lambda_at_edge ||
      (
        var.publish &&
        var.package_type == "Zip" &&
        length(var.environment_variables) == 0 &&
        var.vpc_config == null &&
        length(var.file_system_configs) == 0 &&
        length(var.layers) == 0 &&
        var.dead_letter_target_arn == null &&
        alltrue([for a in var.architectures : a == "x86_64"]) &&
        var.timeout <= 30 &&
        var.memory_size <= 3008
      )
    )
    error_message = "Lambda@Edge mode requires publish=true, package_type='Zip', x86_64 architecture, timeout<=30, memory_size<=3008, and no env vars, VPC config, layers, file system configs, or dead letter target."
  }
}
