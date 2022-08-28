#provider details

provider "google" {
  #credentials = file(var.credentials_file_path)
  project = "control-plane-358307"
  # region = "us-central1"
  # zone = "us-central1-a"
}
# Backend configuration
# terraform {
#   backend "gcs" {
#     bucket      = "control-plane-358307-tf"
#     prefix      = "terraform/state"
#     credentials = "./cred.json"
#   }
# }

module "vpc" {
    source  = "../modules/vpc/"
    project_id   = "control-plane-358307"
    network_name = "k8s-vpc-prod" 
    mtu          = "1460"
    routing_mode = "GLOBAL"
}




module "subnets" {
    source  = "../modules/subnets/"
    project_id   = "control-plane-358307"
    network_name = module.vpc.network_name

    subnets = [
        {
            subnet_name                  = "k8s-private-subnet-01"
            subnet_ip                    = "10.10.10.0/24"
            subnet_region                = "us-central1"
            subnet_flow_logs             = "true"
            subnet_flow_logs_interval    = "INTERVAL_10_MIN"
            subnet_flow_logs_sampling    = 0.7
            subnet_flow_logs_metadata    = "INCLUDE_ALL_METADATA"
            subnet_flow_logs_filter_expr = "true"
        }
    ]

    secondary_ranges = {

       k8s-private-subnet-01 = [
            {
                  range_name    = "k8s-pod-range"
                  ip_cidr_range = "10.48.0.0/14"
              },
             {
                   range_name    = "k8s-service-range"
                   ip_cidr_range = "192.168.63.0/24"
               },
         ]


    }
}

module "router-nat" {
    source  = "../modules/router-nat/"
    project   = "control-plane-358307"
    region   = "us-central1"
    network  = module.vpc.network_name
    name   = "k8s-router"
    subnetwork = "k8s-private-subnet-01"
}

module "firewall_rules" {
  source       = "../modules/firewall/"
  project_id   = "control-plane-358307"
  network_name = module.vpc.network_name
    rules = [{
    name                    = "allow-ssh-ingress"
    description             = null
    direction               = "INGRESS"
    priority                = null
    ranges                  = ["0.0.0.0/0"]
    source_tags             = null
    source_service_accounts = null
    target_tags             = null
    target_service_accounts = null
    allow = [{
      protocol = "tcp"
      ports    = ["22"]
    }]
    deny = []
    log_config = {
      metadata = "INCLUDE_ALL_METADATA"
    }
  }]
}

module "gke" {
  source = "../modules/gke/"
  name                             = "customername-k8s-cluster1"
  region                           = "us-central1"
  project                          = "control-plane-358307"
  kubernetes_version               = "1.22.10-gke.600"
  network_name                     = module.vpc.network_name
  nodes_subnetwork_name            = "k8s-private-subnet-01"
  pods_secondary_ip_range_name     = "k8s-pod-range"
  services_secondary_ip_range_name = "k8s-service-range"
  # private cluster options
  enable_private_endpoint = false
  enable_private_nodes    = true
  master_ipv4_cidr_block  = "10.128.254.0/28"

  master_authorized_network_cidrs = [
    {
# This is the module default, but demonstrates specifying this input.
      cidr_block   = "0.0.0.0/0"
      display_name = "from the Internet"
    },
  ]
}
resource "google_container_node_pool" "node_pool" {
  name     = "k8s-private-pool"
  project  = "control-plane-358307"
  location = "us-central1"
  node_count = "2"
  cluster  =  module.gke.name
  autoscaling {
        min_node_count = 0
        max_node_count = 5
  }
  management {
        auto_repair  = true
        auto_upgrade = true
  }

  node_config {
    machine_type = "e2-small"

    tags         = ["k8s-private-pool"]
    preemptible  = false
    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/servicecontrol",
      "https://www.googleapis.com/auth/service.management.readonly",
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/trace.append",
  ]
  }

}

