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

###############################################################################
## Transit Gateway
###############################################################################
variable "transit_gateway_connection_name_1" {
  type = string
  description = "Name of Transit Gateway connection"
}

variable "transit_gateway_connection_network_type_1" {
  type = string
  description = "Type of network for Transit Gateway connection [i.e. \"vpc\", \"power_virtual_server\", \"directlink\", \"gre_tunnel\", \"unbound_gre_tunnel\", \"classic\"]"
}

variable "transit_gateway_connection_network_id_1" {
  type = string
  description = "CRN of Transit Gateway network connection"
}

variable "transit_gateway_connection_name_2" {
  type = string
  description = "Name of Transit Gateway connection"
}

variable "transit_gateway_connection_network_type_2" {
  type = string
  description = "Type of network for Transit Gateway connection [i.e. \"vpc\", \"power_virtual_server\", \"directlink\", \"gre_tunnel\", \"unbound_gre_tunnel\", \"classic\"]"
}

variable "transit_gateway_connection_network_id_2" {
  type = string
  description = "CRN of Transit Gateway network connection"
}
