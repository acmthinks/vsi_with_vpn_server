variable "ibmcloud_api_key" {}

// If provisioning multiple zones, make sure to choose an MZR.
variable "region" {
   description = "Region of the VPC"
}

variable "resource_group_id" {
   description = "ID of Resource Group in which to provision the VSI."
}

variable "basename" {
   default = "wgm"
   type = string
   description = "Prefix used to name all resources."
}

