data "google_project" "project" {}

#Setup a template for the windows startup bat file.  The bat files calls a powershell script so that is can get permissios to install stackdriver
data "template_file" "windowsstartup" {
  template = "${file("../powershell/windows-stackdriver-setup.ps1")}"

  vars {
    environment = "${var.environment}"
    projectname = "${lower(data.google_project.project.name)}"
    computername = "${var.deployment-name}-${var.environment}-${var.function}-${var.instancerole}-${var.instancenumber}"
  }
}

resource "google_compute_disk" "datadisk" {
  name  = "${var.deployment-name}-${var.environment}-${var.function}-${var.instancerole}-${var.instancenumber}-pd-standard"
  zone = "${var.regionandzone}"
  type  = "pd-standard"
  size = "200"
}

resource "google_compute_instance" "windows"{
  name = "${var.deployment-name}-${var.environment}-${var.function}-${var.instancerole}-${var.instancenumber}"
  machine_type = "${var.machinetype}"
  zone = "${var.regionandzone}"
  boot_disk {
    initialize_params
      {
        image = "${var.osimage}"
        size = "200"
        type = "pd-standard"
      }
  }

  network_interface {
    subnetwork = "${var.subnet-name}"
    access_config {
      // Ephemeral IP
    }
  }
  //network_interface {
  //  network="default"
    //subnetwork = "${var.secondary-subnet-name}"
  //  access_config {
      // Ephemeral IP
  //  }
 // }

  attached_disk {
    source = "${var.deployment-name}-${var.environment}-${var.function}-${var.instancerole}-${var.instancenumber}-pd-standard"
    device_name = "appdata"
  }

  depends_on = [ "google_compute_disk.datadisk"]

  tags= ["${var.network-tag}"]

  metadata {
    environment = "${var.environment}"
    domain-name = "${var.domain-name}"
    function = "${var.function}"
    region = "${var.region}"
    keyring = "${var.keyring}"
    runtime-config = "${var.runtime-config}"
    kms-key = "${var.kms-key}"
    gcs-prefix = "${var.gcs-prefix}"
    netbios-name = "${var.netbios-name}"
    application = "basicwindows"
    windows-startup-script-ps1 = "${data.template_file.windowsstartup.rendered}"
    role = "${var.instancerole}"
  }

  service_account {
    //scopes = ["storage-ro","monitoring-write","logging-write","trace-append"]
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }
}
