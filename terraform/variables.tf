variable "ibmcloud_api_key" {
  type        = string
  description = "IBM Cloud API key"
}

variable "prefix" {
  type        = string
  default = "demo"
  description = "The string that needs to be attached to every resource created"
}

variable "resource_group" {
  type        = string
  default     = "demo-rg"
  description = "Name of the resource group"
}

variable "region" {
  type        = string
  description = "IBM Cloud region to provision the resources."
  default     = "us-south"
}

variable "zone" {
  type        = string
  description = "IBM Cloud availability zone within a region to provision the resources."
  default     = "us-south-1"
}

variable "edge_vpc_address_prefix" {
  type        = string
  description = "IP Address prefix (CIDR)"
  default     = "10.50.0.0/24"
}

variable "edge_vpc_vpn_cidr" {
  type        = string
  description = "IP Address CIDR for the vpn"
  default     = "10.50.0.0/25"
}

variable "edge_vpc_bastion_cidr" {
  type        = string
  description = "IP Address CIDR for bastion or jump host"
  default     = "10.50.0.128/25"
}

variable "edge_vpc_public_cidr" {
  type = string
  description = "IP Address CIDR for public VPN traffic"
  default = "192.168.0.0/16"
}

variable "secrets_manager_instance_crn" {
  type        = string
  description = "CRN of existing Secrets Manager instance"
}

variable "vpn_certificate_crn" {
  type        = string
  description = "CRN of existing VPN certificate instance from Secrets Manager"
}
