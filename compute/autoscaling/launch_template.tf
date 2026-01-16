################################################################################
# Launch Template
################################################################################

resource "aws_launch_template" "this" {
  count = local.create_launch_template ? 1 : 0

  name        = var.name
  description = var.launch_template.description

  image_id      = var.launch_template.image_id
  instance_type = var.launch_template.instance_type
  key_name      = var.launch_template.key_name
  ebs_optimized = var.launch_template.ebs_optimized
  kernel_id     = var.launch_template.kernel_id
  ram_disk_id   = var.launch_template.ram_disk_id

  user_data = var.launch_template.user_data != null ? base64encode(var.launch_template.user_data) : null

  vpc_security_group_ids = length(coalesce(var.launch_template.network_interfaces, [])) == 0 ? var.launch_template.security_group_ids : null

  disable_api_termination = var.launch_template.disable_api_termination
  disable_api_stop        = var.launch_template.disable_api_stop

  update_default_version = var.launch_template.update_default_version

  ################################################################################
  # IAM Instance Profile
  ################################################################################

  dynamic "iam_instance_profile" {
    for_each = var.launch_template.iam_instance_profile_arn != null || var.launch_template.iam_instance_profile_name != null ? [1] : []
    content {
      arn  = var.launch_template.iam_instance_profile_arn
      name = var.launch_template.iam_instance_profile_arn == null ? var.launch_template.iam_instance_profile_name : null
    }
  }

  ################################################################################
  # Network Interfaces
  ################################################################################

  dynamic "network_interfaces" {
    for_each = coalesce(var.launch_template.network_interfaces, [])
    content {
      device_index                = network_interfaces.value.device_index
      description                 = network_interfaces.value.description
      associate_public_ip_address = network_interfaces.value.associate_public_ip_address
      delete_on_termination       = network_interfaces.value.delete_on_termination
      security_groups             = network_interfaces.value.security_groups
      subnet_id                   = network_interfaces.value.subnet_id
      private_ip_address          = network_interfaces.value.private_ip_address
      ipv4_address_count          = network_interfaces.value.ipv4_address_count
      ipv4_prefixes               = network_interfaces.value.ipv4_prefixes
      ipv4_prefix_count           = network_interfaces.value.ipv4_prefix_count
      ipv6_addresses              = network_interfaces.value.ipv6_addresses
      ipv6_address_count          = network_interfaces.value.ipv6_address_count
      ipv6_prefixes               = network_interfaces.value.ipv6_prefixes
      ipv6_prefix_count           = network_interfaces.value.ipv6_prefix_count
      network_interface_id        = network_interfaces.value.network_interface_id
      network_card_index          = network_interfaces.value.network_card_index
      interface_type              = network_interfaces.value.interface_type
    }
  }

  ################################################################################
  # Block Device Mappings
  ################################################################################

  dynamic "block_device_mappings" {
    for_each = coalesce(var.launch_template.block_device_mappings, [])
    content {
      device_name  = block_device_mappings.value.device_name
      no_device    = block_device_mappings.value.no_device
      virtual_name = block_device_mappings.value.virtual_name

      dynamic "ebs" {
        for_each = block_device_mappings.value.ebs != null ? [block_device_mappings.value.ebs] : []
        content {
          volume_size           = ebs.value.volume_size
          volume_type           = ebs.value.volume_type
          iops                  = ebs.value.iops
          throughput            = ebs.value.throughput
          encrypted             = ebs.value.encrypted
          kms_key_id            = ebs.value.kms_key_id
          delete_on_termination = ebs.value.delete_on_termination
          snapshot_id           = ebs.value.snapshot_id
        }
      }
    }
  }

  ################################################################################
  # Metadata Options (IMDSv2)
  ################################################################################

  dynamic "metadata_options" {
    for_each = var.launch_template.metadata_options != null ? [var.launch_template.metadata_options] : []
    content {
      http_endpoint               = metadata_options.value.http_endpoint
      http_tokens                 = metadata_options.value.http_tokens
      http_put_response_hop_limit = metadata_options.value.http_put_response_hop_limit
      http_protocol_ipv6          = metadata_options.value.http_protocol_ipv6
      instance_metadata_tags      = metadata_options.value.instance_metadata_tags
    }
  }

  ################################################################################
  # Monitoring
  ################################################################################

  dynamic "monitoring" {
    for_each = var.launch_template.monitoring_enabled != null ? [1] : []
    content {
      enabled = var.launch_template.monitoring_enabled
    }
  }

  ################################################################################
  # Placement
  ################################################################################

  dynamic "placement" {
    for_each = var.launch_template.placement != null ? [var.launch_template.placement] : []
    content {
      availability_zone       = placement.value.availability_zone
      affinity                = placement.value.affinity
      group_name              = placement.value.group_name
      host_id                 = placement.value.host_id
      host_resource_group_arn = placement.value.host_resource_group_arn
      spread_domain           = placement.value.spread_domain
      tenancy                 = placement.value.tenancy
      partition_number        = placement.value.partition_number
    }
  }

  ################################################################################
  # Instance Market Options (Spot)
  ################################################################################

  dynamic "instance_market_options" {
    for_each = var.launch_template.instance_market_options != null ? [var.launch_template.instance_market_options] : []
    content {
      market_type = instance_market_options.value.market_type

      dynamic "spot_options" {
        for_each = instance_market_options.value.spot_options != null ? [instance_market_options.value.spot_options] : []
        content {
          block_duration_minutes         = spot_options.value.block_duration_minutes
          instance_interruption_behavior = spot_options.value.instance_interruption_behavior
          max_price                      = spot_options.value.max_price
          spot_instance_type             = spot_options.value.spot_instance_type
          valid_until                    = spot_options.value.valid_until
        }
      }
    }
  }

  ################################################################################
  # CPU Options
  ################################################################################

  dynamic "cpu_options" {
    for_each = var.launch_template.cpu_options != null ? [var.launch_template.cpu_options] : []
    content {
      amd_sev_snp      = cpu_options.value.amd_sev_snp
      core_count       = cpu_options.value.core_count
      threads_per_core = cpu_options.value.threads_per_core
    }
  }

  ################################################################################
  # Credit Specification (T2/T3 instances)
  ################################################################################

  dynamic "credit_specification" {
    for_each = var.launch_template.credit_specification != null ? [var.launch_template.credit_specification] : []
    content {
      cpu_credits = credit_specification.value.cpu_credits
    }
  }

  ################################################################################
  # Capacity Reservation Specification
  ################################################################################

  dynamic "capacity_reservation_specification" {
    for_each = var.launch_template.capacity_reservation_specification != null ? [var.launch_template.capacity_reservation_specification] : []
    content {
      capacity_reservation_preference = capacity_reservation_specification.value.capacity_reservation_preference

      dynamic "capacity_reservation_target" {
        for_each = capacity_reservation_specification.value.capacity_reservation_target != null ? [capacity_reservation_specification.value.capacity_reservation_target] : []
        content {
          capacity_reservation_id                 = capacity_reservation_target.value.capacity_reservation_id
          capacity_reservation_resource_group_arn = capacity_reservation_target.value.capacity_reservation_resource_group_arn
        }
      }
    }
  }

  ################################################################################
  # Enclave Options (AWS Nitro Enclaves)
  ################################################################################

  dynamic "enclave_options" {
    for_each = var.launch_template.enclave_options != null ? [var.launch_template.enclave_options] : []
    content {
      enabled = enclave_options.value.enabled
    }
  }

  ################################################################################
  # Hibernation Options
  ################################################################################

  dynamic "hibernation_options" {
    for_each = var.launch_template.hibernation_options != null ? [var.launch_template.hibernation_options] : []
    content {
      configured = hibernation_options.value.configured
    }
  }

  ################################################################################
  # License Specifications
  ################################################################################

  dynamic "license_specification" {
    for_each = coalesce(var.launch_template.license_specifications, [])
    content {
      license_configuration_arn = license_specification.value.license_configuration_arn
    }
  }

  ################################################################################
  # Maintenance Options
  ################################################################################

  dynamic "maintenance_options" {
    for_each = var.launch_template.maintenance_options != null ? [var.launch_template.maintenance_options] : []
    content {
      auto_recovery = maintenance_options.value.auto_recovery
    }
  }

  ################################################################################
  # Private DNS Name Options
  ################################################################################

  dynamic "private_dns_name_options" {
    for_each = var.launch_template.private_dns_name_options != null ? [var.launch_template.private_dns_name_options] : []
    content {
      enable_resource_name_dns_aaaa_record = private_dns_name_options.value.enable_resource_name_dns_aaaa_record
      enable_resource_name_dns_a_record    = private_dns_name_options.value.enable_resource_name_dns_a_record
      hostname_type                        = private_dns_name_options.value.hostname_type
    }
  }

  ################################################################################
  # Instance Requirements (Attribute-based instance type selection)
  ################################################################################

  dynamic "instance_requirements" {
    for_each = var.launch_template.instance_requirements != null ? [var.launch_template.instance_requirements] : []
    content {
      vcpu_count {
        min = instance_requirements.value.vcpu_count.min
        max = instance_requirements.value.vcpu_count.max
      }

      memory_mib {
        min = instance_requirements.value.memory_mib.min
        max = instance_requirements.value.memory_mib.max
      }

      dynamic "accelerator_count" {
        for_each = instance_requirements.value.accelerator_count != null ? [instance_requirements.value.accelerator_count] : []
        content {
          min = accelerator_count.value.min
          max = accelerator_count.value.max
        }
      }

      accelerator_manufacturers = instance_requirements.value.accelerator_manufacturers
      accelerator_names         = instance_requirements.value.accelerator_names

      dynamic "accelerator_total_memory_mib" {
        for_each = instance_requirements.value.accelerator_total_memory_mib != null ? [instance_requirements.value.accelerator_total_memory_mib] : []
        content {
          min = accelerator_total_memory_mib.value.min
          max = accelerator_total_memory_mib.value.max
        }
      }

      accelerator_types       = instance_requirements.value.accelerator_types
      allowed_instance_types  = instance_requirements.value.allowed_instance_types
      bare_metal              = instance_requirements.value.bare_metal

      dynamic "baseline_ebs_bandwidth_mbps" {
        for_each = instance_requirements.value.baseline_ebs_bandwidth_mbps != null ? [instance_requirements.value.baseline_ebs_bandwidth_mbps] : []
        content {
          min = baseline_ebs_bandwidth_mbps.value.min
          max = baseline_ebs_bandwidth_mbps.value.max
        }
      }

      burstable_performance   = instance_requirements.value.burstable_performance
      cpu_manufacturers       = instance_requirements.value.cpu_manufacturers
      excluded_instance_types = instance_requirements.value.excluded_instance_types
      instance_generations    = instance_requirements.value.instance_generations
      local_storage           = instance_requirements.value.local_storage
      local_storage_types     = instance_requirements.value.local_storage_types

      max_spot_price_as_percentage_of_optimal_on_demand_price = instance_requirements.value.max_spot_price_as_percentage_of_optimal_on_demand_price

      dynamic "memory_gib_per_vcpu" {
        for_each = instance_requirements.value.memory_gib_per_vcpu != null ? [instance_requirements.value.memory_gib_per_vcpu] : []
        content {
          min = memory_gib_per_vcpu.value.min
          max = memory_gib_per_vcpu.value.max
        }
      }

      dynamic "network_bandwidth_gbps" {
        for_each = instance_requirements.value.network_bandwidth_gbps != null ? [instance_requirements.value.network_bandwidth_gbps] : []
        content {
          min = network_bandwidth_gbps.value.min
          max = network_bandwidth_gbps.value.max
        }
      }

      dynamic "network_interface_count" {
        for_each = instance_requirements.value.network_interface_count != null ? [instance_requirements.value.network_interface_count] : []
        content {
          min = network_interface_count.value.min
          max = network_interface_count.value.max
        }
      }

      on_demand_max_price_percentage_over_lowest_price = instance_requirements.value.on_demand_max_price_percentage_over_lowest_price
      require_hibernate_support                        = instance_requirements.value.require_hibernate_support
      spot_max_price_percentage_over_lowest_price      = instance_requirements.value.spot_max_price_percentage_over_lowest_price

      dynamic "total_local_storage_gb" {
        for_each = instance_requirements.value.total_local_storage_gb != null ? [instance_requirements.value.total_local_storage_gb] : []
        content {
          min = total_local_storage_gb.value.min
          max = total_local_storage_gb.value.max
        }
      }
    }
  }

  ################################################################################
  # Tag Specifications
  ################################################################################

  dynamic "tag_specifications" {
    for_each = coalesce(var.launch_template.tag_specifications, [])
    content {
      resource_type = tag_specifications.value.resource_type
      tags          = tag_specifications.value.tags
    }
  }

  ################################################################################
  # Tags and Lifecycle
  ################################################################################

  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}
