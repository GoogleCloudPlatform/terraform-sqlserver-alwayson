data "google_project" "project" {}
data "template_file" "windowsstartupwsus" {
  template = "${file("../powershell/windowsstartupwsus.ps1")}"
  vars {
    environment = "${var.environment}"
    dnsserver1 = "${var.dnsserver1}"
    dnsserver2 = "${var.dnsserver2}"
    projectname = "${lower(data.google_project.project.name)}"
    number = "${var.instancenumber}"
  }
}
resource "google_compute_instance" "wsus"{
  name = "${var.deployment-name}${var.environment}-${var.instancerole}-wsus${var.instancenumber}"
  machine_type = "${var.machinetype}"
  zone = "${var.regionandzone}"
  boot_disk {
    initialize_params
      {
        image = "${var.osimage}"
        size = "400"
        type = "pd-standard"
      }
  }
  network_interface {
    subnetwork = "${lower(data.google_project.project.name)}-vpc-${substr(var.regionandzone,0,length(var.regionandzone)-2)}-${var.assignedsubnet}"
    #subnetwork = "default"
    access_config {
      // Ephemeral IP
    }
  }
  tags = ["windowsupdate-server"]
  metadata {
    applicationstack="wsus"
    environment = "${var.environment}"
    application = "wsus"
    windows-startup-script-ps1 = "${data.template_file.windowsstartupwsus.rendered}"
    role = "${var.instancerole}"
  }
  service_account {
    scopes = ["storage-ro","monitoring-write","logging-write","trace-append"]
  }
}
