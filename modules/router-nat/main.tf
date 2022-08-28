resource "google_compute_router" "k8s-router" {
  name        = var.name
  network     = var.network
  region      = var.region
  project     = var.project
  description = var.description
  dynamic "bgp" {
    for_each = var.bgp != null ? [var.bgp] : []
    content {
      asn = var.bgp.asn

      # advertise_mode is intentionally set to CUSTOM to not allow "DEFAULT".
      # This forces the config to explicitly state what subnets and ip ranges
      # to advertise. To advertise the same range as DEFAULT, set
      # `advertise_groups = ["ALL_SUBNETS"]`.
      advertise_mode     = "CUSTOM"
      advertised_groups  = lookup(var.bgp, "advertised_groups", null)
      keepalive_interval = lookup(var.bgp, "keepalive_interval", null)

      dynamic "advertised_ip_ranges" {
        for_each = lookup(var.bgp, "advertised_ip_ranges", [])
        content {
          range       = advertised_ip_ranges.value.range
          description = lookup(advertised_ip_ranges.value, "description", null)
        }
      }
    }
  }
}
resource "google_compute_router_nat" "k8s-nat-router" {
  name                               = "k8s-nat-router"
  router                             = google_compute_router.k8s-router.name
  region                             = google_compute_router.k8s-router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = var.subnetwork
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
