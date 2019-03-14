output "subnet-name" {
  value = "${google_compute_subnetwork.primary-subnetwork.name}"
  #value = "test-string"
}
output "second-subnet-name" {
  value = "${google_compute_subnetwork.subnetwork-2.name}"
  #value = "test-string"
}
output "third-subnet-name" {
  value = "${google_compute_subnetwork.subnetwork-3.name}"
  #value = "test-string"
}
output "fourth-subnet-name" {
  value = "${google_compute_subnetwork.subnetwork-4.name}"
  #value = "test-string"
}
