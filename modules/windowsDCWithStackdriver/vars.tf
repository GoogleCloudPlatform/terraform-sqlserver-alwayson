variable "machinetype" {type = "string" default = "n1-standard-4" }
variable "osimage" {type = "string"}
variable "environment" {type = "string" }
variable "instancerole" {type = "string" default = "p"}
variable "function" {type = "string" default = "pdc"}
variable "instancenumber" {type = "string" default = "01"}
variable "regionandzone" {type = "string"}
variable "deployment-name" {type = "string" default = ""}
variable "assignedsubnet" {type = "string" default = "default"}
variable "domain-name" {type="string" default = "test-domain"}
variable "kms-key" {type="string" default = "p@ssword"}
variable "gcs-prefix" {type="string"}
variable "region" {type="string"}
variable "subnet-name" {type="string"}
variable "secondary-subnet-name" {type="string"}
variable "netbios-name" {type="string"}
variable "runtime-config" {type="string"}
variable "keyring" {type="string"}
variable "wait-on" {type="string"}
variable "status-variable-path" {type="string"}
variable "network-tag" {type="list" default=[""] description="network tags"}
variable "network-ip" {type="string" default=""}
#variable "project-id" {type="string"}
