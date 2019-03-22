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
  project = "{cloud-project-id}"
  region = "{cloud-project-region}"
}

locals {
  primaryzone = "{cloud-project-zone}"
  region      = "{cloud-project-region}"
  deployment-name = "c2d"
  environment = "dev"
  osimagelinux = "projects/eip-images/global/images/rhel-7-drawfork-v20180327"
  osimageWindows = "windows-server-2016-dc-v20181009"
  osimageSQL = "projects/windows-sql-cloud/global/images/sql-2017-enterprise-windows-2016-dc-v20181009"
  gcs-prefix = "gs://{deployment-name}-deployment-staging"
  keyring = "{deployment-name}-deployment-ring"
  kms-key = "{deployment-name}-deployment-key"
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
  domain = "{deployment-name}.com"
  dc-netbios-name = "{deployment-name}"
  runtime-config = "{deployment-name}-runtime-config"
  all_nodes="c2d-sql-01|cd2-sql-02|c2d-sql-03"
}

module "create-network"{
  source = "../modules/network"
  network-name   = "${local.deployment-name}-${local.environment}-net"
  primary-cidr   = "${local.primary-cidr}"
  second-cidr = "${local.second-cidr}"
  third-cidr = "${local.third-cidr}"
  fourth-cidr = "${local.fourth-cidr}"
  region         = "${local.region}"
}

//windows domain controller
module "windows-domain-controller" {
  source          = "../modules/windowsDCWithStackdriver"
  subnet-name     = "${module.create-network.subnet-name}"
  secondary-subnet-name = "${module.create-network.subnet-name}"
  instancerole    = "p"
  instancenumber  = "01"
  function        = "pdc"
  region          = "${local.region}"
  keyring         = "${local.keyring}"
  kms-key         = "${local.kms-key}"
  environment     = "${local.environment}"
  regionandzone   = "${local.primaryzone}"
  osimage         = "${local.osimageWindows}"
  gcs-prefix      = "${local.gcs-prefix}"
  deployment-name = "${local.deployment-name}"
  domain-name     = "${local.domain}"
  netbios-name    = "${local.dc-netbios-name}"
  runtime-config  = "${local.runtime-config}"
  wait-on         = ""
  status-variable-path = "ad"
  network-tag     = ["pdc"]
  network-ip      = "10.0.0.100"
}

module "sql-server-alwayson-primary" {
  source = "../modules/SQLServerWithStackdriver"
  subnet-name = "${module.create-network.second-subnet-name}"
  alwayson-vip = "${local.second-cidr-alwayson}"
  wsfc-vip = "${local.second-cidr-wsfc}"
  instancerole = "p"
  instancenumber = "01"
  function = "sql"
  region = "${local.region}"
  keyring = "${local.keyring}"
  kms-key = "${local.kms-key}"
  environment = "${local.environment}"
  regionandzone = "${local.primaryzone}"
  osimage = "${local.osimageSQL}"
  gcs-prefix = "${local.gcs-prefix}"
  deployment-name = "${local.deployment-name}"
  domain-name = "${local.domain}"
  netbios-name = "${local.dc-netbios-name}"
  runtime-config = "${local.runtime-config}"
  wait-on = "bootstrap/${local.deployment-name}/ad/success"
  domain-controller-address = "${module.windows-domain-controller.dc-address}"
  post-join-script-url = "${local.gcs-prefix}/powershell/bootstrap/install-sql-server-principal-step-1.ps1"
  status-variable-path = "mssql"
  network-tag = ["sql", "internal"]
  sql_nodes="${local.deployment-name}-sql-01|${local.deployment-name}-sql-02|${local.deployment-name}-sql-03"

}

 module "sql-server-alwayson-secondary" {
  source = "../modules/SQLServerWithStackdriver"
  subnet-name = "${module.create-network.third-subnet-name}"
  instancerole = "s"
  instancenumber = "02"
  function = "sql"
  region = "${local.region}"
  keyring = "${local.keyring}"
  kms-key = "${local.kms-key}"
  environment = "${local.environment}"
  regionandzone = "${local.primaryzone}"
  osimage = "${local.osimageSQL}"
  gcs-prefix = "${local.gcs-prefix}"
  deployment-name = "${local.deployment-name}"
  domain-name = "${local.domain}"
  netbios-name = "${local.dc-netbios-name}"
  runtime-config = "${local.runtime-config}"
  wait-on = "bootstrap/${local.deployment-name}/ad/success"
  domain-controller-address = "${module.windows-domain-controller.dc-address}"
  post-join-script-url = "${local.gcs-prefix}/powershell/bootstrap/install-sql-server-principal-step-1.ps1"
  status-variable-path = "mssql"
  network-tag = ["sql", "internal"]
  sql_nodes="${local.deployment-name}-sql-01|${local.deployment-name}-sql-02|${local.deployment-name}-sql-03"
  alwayson-vip = "${local.third-cidr-alwayson}"
  wsfc-vip = "${local.third-cidr-wsfc}"
}

 module "sql-server-alwayson-secondary-2" {
  source = "../modules/SQLServerWithStackdriver"
  subnet-name = "${module.create-network.fourth-subnet-name}"
  instancerole = "s"
  instancenumber = "03"
  function = "sql"
  region = "${local.region}"
  keyring = "${local.keyring}"
  kms-key = "${local.kms-key}"
  environment = "${local.environment}"
  regionandzone = "${local.primaryzone}"
  osimage = "${local.osimageSQL}"
  gcs-prefix = "${local.gcs-prefix}"
  deployment-name = "${local.deployment-name}"
  domain-name = "${local.domain}"
  netbios-name = "${local.dc-netbios-name}"
  runtime-config = "${local.runtime-config}"
  wait-on = "bootstrap/${local.deployment-name}/ad/success"
  domain-controller-address = "${module.windows-domain-controller.dc-address}"
  post-join-script-url = "${local.gcs-prefix}/powershell/bootstrap/install-sql-server-principal-step-1.ps1"
  status-variable-path = "mssql"
  network-tag = ["sql", "internal"]
  sql_nodes="${local.deployment-name}-sql-01|${local.deployment-name}-sql-02|${local.deployment-name}-sql-03"
  alwayson-vip = "${local.fourth-cidr-alwayson}"
  wsfc-vip = "${local.fourth-cidr-wsfc}"
}
