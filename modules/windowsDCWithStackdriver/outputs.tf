locals{
  nic = "${google_compute_instance.domain-controller.network_interface[0]}"
}

output "dc-address" {
  value = "${lookup(local.nic, "network_ip")}"
}
