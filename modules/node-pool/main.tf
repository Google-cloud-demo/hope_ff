locals {
  base_oauth_scopes = [
    "https://www.googleapis.com/auth/logging.write",
    "https://www.googleapis.com/auth/monitoring",
    "https://www.googleapis.com/auth/servicecontrol",
    "https://www.googleapis.com/auth/service.management.readonly",
    "https://www.googleapis.com/auth/devstorage.read_only",
    "https://www.googleapis.com/auth/trace.append",
  ]

  oauth_scopes = var.oauth_scopes != null ? var.oauth_scopes : compact(concat(local.base_oauth_scopes, var.additional_oauth_scopes))

  node_pools = { for node in var.node_pools : node.name => node }
}

resource "google_container_node_pool" "current" {
  for_each = local.node_pools

  project = var.project
  cluster = var.cluster_name

  name        = try(each.value.name, null)
  name_prefix = try(each.value.name_prefix, null)
  version = try(each.value.auto_upgrade, false) ? null : try(each.value.kubernetes_version, var.kubernetes_version)

  location       = try(each.value.location, var.location, null)
  node_locations = try(each.value.node_locations, var.node_locations, null)

  autoscaling {
    min_node_count = try(each.value.min_node_count, 0)
    max_node_count = try(each.value.max_node_count, each.value.initial_node_count, each.value.min_node_count, 2)
  }

  max_pods_per_node = try(each.value.max_pods_per_node, null)

  upgrade_settings {
    max_surge       = try(each.value.max_surge, var.max_surge)
    max_unavailable = try(each.value.max_unavailable, var.max_unavailable)
  }

  management {
    auto_repair  = try(each.value.auto_repair, true)
    auto_upgrade = try(each.value.auto_upgrade, false)
  }

  node_config {
    service_account = try(each.value.service_account, var.service_account)

    oauth_scopes = try(each.value.oauth_scopes, local.oauth_scopes)

    local_ssd_count = try(each.value.local_ssd_count, 0)
    disk_size_gb    = try(each.value.disk_size_gb, 100)
    disk_type       = try(each.value.disk_type, "pd-standard")

    image_type   = try(each.value.image_type, "COS")
    machine_type = try(each.value.machine_type, "e2-medium")
    preemptible  = try(each.value.preemptible, false)
    tags = distinct(compact(concat(tolist(var.tags), try(tolist(each.value.tags), []))))

    metadata = merge(var.metadata, try(each.value.metadata, {}), {
      "disable-legacy-endpoints" = true
    })

    min_cpu_platform = try(each.value.min_cpu_platform, null)

    shielded_instance_config {
      enable_secure_boot          = try(each.value.enable_secure_boot, false)
      enable_integrity_monitoring = try(each.value.enable_integrity_monitoring, true)
    }
    guest_accelerator = try(each.value.guest_accelerator, [])
  }

  # DO NOT USE: initial_node_count due to it's destructive behavior
  # initial_node_count = null
  initial_node_count = try(each.value.initial_node_count, 1)
  lifecycle {
    ignore_changes = [initial_node_count]
  }
}