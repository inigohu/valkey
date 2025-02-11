terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "6.18.0"
    }
  }
}

variable "project_id" {
  type = string
}

locals {
  project_services = []
  clusters = {
    "valkey" = {
      region        = "europe-west1"
      network_range = 0
    }
  }
  service_accounts = [
    "workload-valkey",
  ]
  iam_policies = {
    "serviceAccount:${var.project_id}.svc.id.goog[valkey/valkey]"              = ["roles/iam.workloadIdentityUser"]
    "serviceAccount:workload-valkey@${var.project_id}.iam.gserviceaccount.com" = ["roles/memorystore.dbConnectionUser"]
    # "serviceAccount:workload-valkey@${var.project_id}.iam.gserviceaccount.com" = ["roles/memorystore.admin"]
    # "serviceAccount:workload-valkey@${var.project_id}.iam.gserviceaccount.com" = ["roles/editor"]
  }
}

locals {
  iam_binding_project = flatten([for member, roles in local.iam_policies :
    [for role in roles :
      {
        member = member
        role   = role
      }
    ]
  ])
}

data "google_project" "this" {
  project_id = var.project_id
}

# Enable required services on the project
resource "google_project_service" "this" {
  for_each = toset(local.project_services)

  project = data.google_project.this.project_id
  service = each.key

  # Do not disable the service on destroy. On destroy, we aren't going to
  # destroy the project, but we need the APIs available to destroy the
  # underlying resources.
  disable_on_destroy = false
}

resource "google_service_account" "this" {
  for_each = toset(local.service_accounts)

  project      = data.google_project.this.project_id
  account_id   = each.key
  display_name = each.key

  depends_on = [google_project_service.this]
}

resource "google_project_iam_member" "this" {
  for_each = { for policy in local.iam_binding_project : format("%s|%s", policy.member, policy.role) => policy }

  project = data.google_project.this.project_id
  role    = each.value.role
  member  = each.value.member

  depends_on = [google_service_account.this]
}

resource "google_compute_network" "this" {
  for_each = { for key, cluster in local.clusters : key => cluster }

  project                 = data.google_project.this.project_id
  name                    = each.key
  auto_create_subnetworks = "false"
  routing_mode            = "GLOBAL"
  mtu                     = 0

  depends_on = [google_project_service.this]
}

resource "google_compute_subnetwork" "this" {
  for_each = { for key, cluster in local.clusters : key => cluster }

  project                  = data.google_project.this.project_id
  region                   = each.value.region
  name                     = each.key
  ip_cidr_range            = "10.${each.value.network_range}.96.0/22"
  private_ip_google_access = "true"
  network                  = google_compute_network.this[each.key].name

  secondary_ip_range {
    range_name    = "${each.key}-pods"
    ip_cidr_range = "10.${each.value.network_range}.92.0/22"
  }
  secondary_ip_range {
    range_name    = "${each.key}-services"
    ip_cidr_range = "10.${each.value.network_range}.88.0/22"
  }
}

resource "google_compute_firewall" "this" {
  for_each = { for key, cluster in local.clusters : key => cluster }

  project       = data.google_project.this.project_id
  name          = "gke-${each.key}"
  network       = google_compute_network.this[each.key].name
  priority      = 1000
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]

  allow {
    protocol = "tcp"
    ports    = []
  }
}

resource "google_compute_router" "this" {
  for_each = { for key, cluster in local.clusters : key => cluster }

  project = data.google_project.this.project_id
  region  = each.value.region
  name    = each.key
  network = google_compute_network.this[each.key].name
}

resource "google_compute_router_nat" "this" {
  for_each = { for key, cluster in local.clusters : key => cluster }

  project                            = data.google_project.this.project_id
  region                             = google_compute_router.this[each.key].region
  name                               = each.key
  router                             = google_compute_router.this[each.key].name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.this[each.key].name
    source_ip_ranges_to_nat = ["PRIMARY_IP_RANGE", "LIST_OF_SECONDARY_IP_RANGES"]
    secondary_ip_range_names = [
      google_compute_subnetwork.this[each.key].secondary_ip_range[0].range_name,
      google_compute_subnetwork.this[each.key].secondary_ip_range[1].range_name
    ]
  }
}

resource "google_container_cluster" "this" {
  for_each = { for key, cluster in local.clusters : key => cluster }

  project          = data.google_project.this.project_id
  name             = each.key
  location         = each.value.region
  enable_autopilot = true
  network          = google_compute_network.this[each.key].name
  subnetwork       = google_compute_subnetwork.this[each.key].name

  release_channel {
    channel = "REGULAR"
  }

  maintenance_policy {
    recurring_window {
      start_time = "2024-06-01T07:00:00Z" # 8:00 AM CET and 9:00 PM CEST
      end_time   = "2024-06-01T15:00:00Z" # 4:00 PM CET and 5:00 PM CEST
      recurrence = "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"
    }
  }

  vertical_pod_autoscaling {
    enabled = true
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = google_compute_subnetwork.this[each.key].secondary_ip_range[0].range_name
    services_secondary_range_name = google_compute_subnetwork.this[each.key].secondary_ip_range[1].range_name
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "10.0.0.0/28"
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "Anyone"
    }
  }
}

resource "google_network_connectivity_service_connection_policy" "this" {
  for_each = { for key, cluster in local.clusters : key => cluster }

  project       = data.google_project.this.project_id
  name          = each.key
  location      = each.value.region
  service_class = "gcp-memorystore"
  description   = "my basic service connection policy"
  network       = google_compute_network.this[each.key].id
  psc_config {
    subnetworks = [google_compute_subnetwork.this[each.key].id]
  }
}

resource "google_memorystore_instance" "this" {
  for_each = { for key, cluster in local.clusters : key => cluster }

  project     = data.google_project.this.project_id
  instance_id = each.key
  shard_count = 1
  desired_psc_auto_connections {
    network    = google_compute_network.this[each.key].id
    project_id = data.google_project.this.project_id
  }
  location                    = each.value.region
  replica_count               = 1
  node_type                   = "SHARED_CORE_NANO"
  transit_encryption_mode     = "SERVER_AUTHENTICATION"
  authorization_mode          = "IAM_AUTH"
  engine_version              = "VALKEY_8_0"
  deletion_protection_enabled = false
  mode                        = "CLUSTER"
  depends_on = [
    google_network_connectivity_service_connection_policy.this
  ]

  lifecycle {
    prevent_destroy = "true"
  }
}
