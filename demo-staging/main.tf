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
// Configure the Google Cloud provider
provider "google" {
  project = var.project-id
  region = var.region
}



locals {
  primaryzone = var.primaryzone
  region      = var.region
  hazone      = var.hazone
  drregion      = var.drregion
  drzone      = var.drzone
  deployment-name = var.deployment-name
  environment = "dev"
  osimageWindows = "windows-server-2016-dc-v20181009"
  osimageSQL = "projects/windows-sql-cloud/global/images/sql-2017-enterprise-windows-2016-dc-v20181009"
  gcs-prefix = "gs://${google_storage_bucket.bootstrap.name}"
  keyring = "${var.deployment-name}-deployment-key-ring"
  kms-key = "${var.deployment-name}-deployment-key"
  primary-cidr = "10.0.0.0/16"
  second-cidr  = "10.1.0.0/16"
  second-cidr-alwayson = "10.1.0.5/32"
  second-cidr-wsfc = "10.1.0.4/32"
  third-cidr   = "10.2.0.0/16"
  third-cidr-alwayson = "10.2.0.5/32"
  third-cidr-wsfc = "10.2.0.4/32"
  fourth-cidr  = "10.3.0.0/16"
  fourth-cidr-alwayson = "10.3.0.5/32"
  fourth-cidr-wsfc = "10.3.0.4/32"
  domain = "${var.windows-domain}.com"
  dc-netbios-name = var.windows-domain
  runtime-config = "${var.deployment-name}-runtime-config"
  all_nodes="${var.deployment-name}-sql-01|${var.deployment-name}-sql-02|${var.deployment-name}-sql-03"
}

resource "random_uuid" "random_uuid" { }

resource "google_storage_bucket" "bootstrap" {
  name     = "${var.project-id}-mssql-${random_uuid.random_uuid.result}"
  provisioner "local-exec" {
    command = "gsutil -m cp -r ../powershell/bootstrap/* gs://${google_storage_bucket.bootstrap.name}/powershell/bootstrap/"
  }
}

resource "google_service_account" "sa-admin" {
  account_id   = "admin-${local.deployment-name}"
  display_name = "Admin service account for bootstrapping domain-joined servers with elevated permissions"
}

resource "google_service_account_iam_binding" "sa-binding" {
  service_account_id = "${google_service_account.sa-admin.name}"
  role               = "roles/editor"

  members = []
}

resource "google_kms_key_ring" "mssql-key-ring" {
  name     = local.keyring
  location = "global"

  depends_on = [google_project_service.cloudkms, google_project_service.runtimeconfig, google_project_service.cloudresourcemanager,
              google_project_service.iam, google_project_service.compute]
  
}

resource "google_kms_crypto_key" "mssql-kms-key" {
  name            = local.kms-key
  key_ring        = google_kms_key_ring.mssql-key-ring.self_link

  purpose = "ENCRYPT_DECRYPT"

  lifecycle {
    #prevent_destroy = true
  }
}

resource "google_kms_crypto_key_iam_binding" "decrypter-access" {
  crypto_key_id = google_kms_crypto_key.mssql-kms-key.self_link
  role          = "roles/cloudkms.cryptoKeyDecrypter"

  members = [
    "serviceAccount:${google_service_account.sa-admin.email}"
  ]
}

resource "google_kms_crypto_key_iam_binding" "encrypter-access" {
  crypto_key_id = google_kms_crypto_key.mssql-kms-key.self_link
  role          = "roles/cloudkms.cryptoKeyEncrypter"

  members = [
    "serviceAccount:${google_service_account.sa-admin.email}"
  ]
}

resource "google_project_service" "runtimeconfig" {

  service = "runtimeconfig.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudresourcemanager" {

  service = "cloudresourcemanager.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "iam" {

  service = "iam.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudkms" {

  service = "cloudkms.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "compute" {

  service = "compute.googleapis.com"
  disable_on_destroy = false
}


module "create-network"{
  source = "../modules/network"
  custom-depends-on = [google_project_service.compute, google_project_service.runtimeconfig,
      google_project_service.iam, google_project_service.cloudkms, google_project_service.cloudresourcemanager]
  network-name    = "${var.deployment-name}-${local.environment}-net"
  primary-cidr    = local.primary-cidr
  second-cidr     = local.second-cidr
  third-cidr      = local.third-cidr
  fourth-cidr     = local.fourth-cidr
  primary-region  = local.region
  dr-region       = local.drregion
  deployment-name = local.deployment-name
}

//windows domain controller
module "windows-domain-controller" {
  source          = "../modules/windowsDCWithStackdriver"
  custom-depends-on = [google_project_service.compute, google_project_service.runtimeconfig,
      google_project_service.iam, google_project_service.cloudkms, google_project_service.cloudresourcemanager]
  subnet-name     = module.create-network.subnet-name
  secondary-subnet-name = module.create-network.subnet-name
  instancerole    = "p"
  instancenumber  = "01"
  function        = "pdc"
  region          = "${local.region}"
  keyring         = google_kms_key_ring.mssql-key-ring.name
  kms-key         = local.kms-key
  kms-region      = local.region
  environment     = local.environment
  regionandzone   = local.primaryzone
  osimage         = local.osimageWindows
  gcs-prefix      = local.gcs-prefix
  deployment-name = local.deployment-name
  domain-name     = local.domain
  netbios-name    = local.dc-netbios-name
  runtime-config  = local.runtime-config
  wait-on         = ""
  status-variable-path = "ad"
  network-tag     = ["pdc"]
  network-ip      = "10.0.0.100"


}

module "sql-server-alwayson-primary" {
  source = "../modules/SQLServerWithStackdriver"
  custom-depends-on = [google_project_service.compute, google_project_service.runtimeconfig,
      google_project_service.iam, google_project_service.cloudkms, google_project_service.cloudresourcemanager]
  subnet-name = module.create-network.second-subnet-name
  alwayson-vip = local.second-cidr-alwayson
  wsfc-vip = local.second-cidr-wsfc
  instancerole = "p"
  instancenumber = "01"
  function = "sql"
  region = local.region
  keyring = google_kms_key_ring.mssql-key-ring.name
  kms-key = local.kms-key
  kms-region= local.region
  environment = local.environment
  regionandzone = local.primaryzone
  osimage = local.osimageSQL
  gcs-prefix = local.gcs-prefix
  deployment-name = local.deployment-name
  domain-name = local.domain
  netbios-name = local.dc-netbios-name
  runtime-config = local.runtime-config
  wait-on = "bootstrap/${local.deployment-name}/ad/success"
  domain-controller-address = module.windows-domain-controller.dc-address
  post-join-script-url = "${local.gcs-prefix}/powershell/bootstrap/install-sql-server-principal-step-1.ps1"
  status-variable-path = "mssql"
  network-tag = ["sql", "internal"]
  sql_nodes= "${local.deployment-name}-sql-01|${local.deployment-name}-sql-02|${local.deployment-name}-sql-03"

}

 module "sql-server-alwayson-secondary" {
  source = "../modules/SQLServerWithStackdriver"
    custom-depends-on = [google_project_service.compute, google_project_service.runtimeconfig,
      google_project_service.iam, google_project_service.cloudkms, google_project_service.cloudresourcemanager]
  subnet-name = module.create-network.third-subnet-name
  instancerole = "s"
  instancenumber = "02"
  function = "sql"
  region = local.region
  keyring = google_kms_key_ring.mssql-key-ring.name
  kms-key = local.kms-key
  kms-region= local.region
  environment = local.environment
  regionandzone = local.hazone
  osimage = local.osimageSQL
  gcs-prefix = local.gcs-prefix
  deployment-name = local.deployment-name
  domain-name = local.domain
  netbios-name = local.dc-netbios-name
  runtime-config = local.runtime-config
  wait-on = "bootstrap/${local.deployment-name}/ad/success"
  domain-controller-address = module.windows-domain-controller.dc-address
  post-join-script-url = "${local.gcs-prefix}/powershell/bootstrap/install-sql-server-principal-step-1.ps1"
  status-variable-path = "mssql"
  network-tag = ["sql", "internal"]
  sql_nodes= "${local.deployment-name}-sql-01|${local.deployment-name}-sql-02|${local.deployment-name}-sql-03"
  alwayson-vip = local.third-cidr-alwayson
  wsfc-vip = local.third-cidr-wsfc
}

 module "sql-server-alwayson-secondary-2" {
  source = "../modules/SQLServerWithStackdriver"
    custom-depends-on = [google_project_service.compute, google_project_service.runtimeconfig,
      google_project_service.iam, google_project_service.cloudkms, google_project_service.cloudresourcemanager]
  subnet-name = module.create-network.fourth-subnet-name
  instancerole = "s"
  instancenumber = "03"
  function = "sql"
  region = local.drregion
  keyring = google_kms_key_ring.mssql-key-ring.name
  kms-key = local.kms-key
  kms-region= local.region
  environment = local.environment
  regionandzone = local.drzone
  osimage = local.osimageSQL
  gcs-prefix = local.gcs-prefix
  deployment-name = local.deployment-name
  domain-name = local.domain
  netbios-name = local.dc-netbios-name
  runtime-config = local.runtime-config
  wait-on = "bootstrap/${local.deployment-name}/ad/success"
  domain-controller-address = module.windows-domain-controller.dc-address
  post-join-script-url = "${local.gcs-prefix}/powershell/bootstrap/install-sql-server-principal-step-1.ps1"
  status-variable-path = "mssql"
  network-tag = ["sql", "internal"]
  sql_nodes= "${local.deployment-name}-sql-01|${local.deployment-name}-sql-02|${local.deployment-name}-sql-03"
  alwayson-vip = local.fourth-cidr-alwayson
  wsfc-vip = local.fourth-cidr-wsfc
}
