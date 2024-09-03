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

#variable "vpn_certificate_crn" {
#  type        = string
#  description = "CRN of existing VPN certificate instance from Secrets Manager"
#}

## Reserved Endpoints

#Must also leave open: port 53/UDP/DNS, port 80/TCP/HTTP, port 443/TCP/HTTPS, port 8443/TCP/HTTPS (for linux) for IaaS service endpoints to work
#more info at https://cloud.ibm.com/docs/vpc?topic=vpc-service-endpoints-for-vpc
variable "iaas-service-endpoint-cidr" {
  type = string
  description = "Infrastructure services are available by using certain DNS names from the adn.networklayer.com domain, and they resolve to 161.26.0.0/16 addresses. Services that you can reach include: DNS resolvers, Ubuntu and Debian APT mirrors, NTP, IBM COS."
  default = "161.26.0.0/16"
}
variable "wpp-collection-endpoint-cidr-1" {
  type        = string
  description = "IBM Cloud Security and Compliance Center - Workload Protection collection endpoint #1"
  default = "166.9.228.45/32"
}
variable "wpp-collection-endpoint-cidr-2" {
  type        = string
  description = "IBM Cloud Security and Compliance Center - Workload Protection collection endpoint #2"
  default = "166.9.229.45/32"
}
variable "wpp-collection-endpoint-cidr-3" {
  type        = string
  description = "IBM Cloud Security and Compliance Center - Workload Protection collection endpoint #3"
  default = "166.9.230.45/32"
}

variable "wpp-collection-endpoint-cidr-1-deprecated" {
  type        = string
  description = "IBM Cloud Security and Compliance Center - Workload Protection collection endpoint #1 (deprecated)"
  default = "166.9.14.170/32"
}
variable "wpp-collection-endpoint-cidr-2-deprecated" {
  type        = string
  description = "IBM Cloud Security and Compliance Center - Workload Protection collection endpoint #2 (deprecated)"
  default = "166.9.48.41/32"
}
variable "wpp-collection-endpoint-cidr-3-deprecated" {
  type        = string
  description = "IBM Cloud Security and Compliance Center - Workload Protection collection endpoint #3 (deprecated)"
  default = "166.9.17.11/32"
}

variable "wpp-collection-endpoint-port" {
  type        = number
  description = "IBM Cloud Security and Compliance Center - Workload Protection collection endpoint port"
  default = 6443
}
