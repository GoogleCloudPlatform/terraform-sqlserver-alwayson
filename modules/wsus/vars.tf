variable "machinetype" {type = "string" default = "n1-standard-4" }
variable "osimage" {type = "string" default = "windows-server-2016-dc-v20180710"}
variable "environment" {type = "string" }
variable "instancerole" {type = "string" default = "p"}
variable "instancenumber" {type = "string" default = "01"}
variable "regionandzone" {type = "string"}
variable "deployment-name" {type = "string" default = ""}
variable "dnsserver1" {type = "string" default = ""}
variable "dnsserver2" {type = "string" default = ""}
