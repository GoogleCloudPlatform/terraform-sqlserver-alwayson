resource "google_compute_subnetwork" "primary-subnetwork" {
  name          = "${var.network-name}-subnet-1"
  ip_cidr_range = "${var.primary-cidr}"
  region        = "${var.region}"
  network       = "${google_compute_network.custom-network.self_link}"
}

resource "google_compute_subnetwork" "subnetwork-2" {
  name          = "${var.network-name}-subnet-2"
  ip_cidr_range = "${var.second-cidr}"
  region        = "${var.region}"
  network       = "${google_compute_network.custom-network.self_link}"
}

resource "google_compute_subnetwork" "subnetwork-3" {
  name          = "${var.network-name}-subnet-3"
  ip_cidr_range = "${var.third-cidr}"
  region        = "${var.region}"
  network       = "${google_compute_network.custom-network.self_link}"
}

resource "google_compute_subnetwork" "subnetwork-4" {
  name          = "${var.network-name}-subnet-4"
  ip_cidr_range = "${var.fourth-cidr}"
  region        = "${var.region}"
  network       = "${google_compute_network.custom-network.self_link}"
}

resource "google_compute_network" "custom-network" {
  name                    = "${var.network-name}"
  auto_create_subnetworks = false
}

resource "google_compute_firewall" "default" {
  name    = "allow-remote-access"
  network = "${google_compute_network.custom-network.self_link}"


  allow {
    protocol = "tcp"
    ports    = ["3389", "8080"]
  }

  source_ranges = ["35.227.153.235/32"]
  target_tags = ["web","pdc","sql"]
}

resource "google_compute_firewall" "allow-internal" {
  name    = "allow-internal"
  network = "${google_compute_network.custom-network.self_link}"

  allow {
    protocol = "all"
  }

  source_tags = ["pdc","sql"]
  target_tags = ["sql","pdc"]
}

resource "google_compute_firewall" "healthchecks" {
  name    = "allow-healthcheck-access"
  network = "${google_compute_network.custom-network.self_link}"


  allow {
    protocol = "tcp"
    ports    = ["1-65535"]
  }

  source_ranges = ["130.211.0.0/22","35.191.0.0/16"]
  target_tags = ["sql"]
}

resource "google_compute_firewall" "alwayson" {
  name    = "allow-alwayson-access"
  network = "${google_compute_network.custom-network.self_link}"


  allow {
    protocol = "tcp"
    ports    = ["5022"]
  }

  source_tags = ["sql"]
  target_tags = ["sql"]
}
