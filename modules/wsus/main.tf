#
#  Copyright 2019 Google Inc.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#
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
