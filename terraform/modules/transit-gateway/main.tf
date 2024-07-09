/**
 * @author Andrea C. Crawford
 * @email acm@us.ibm.com
 * @create date 2023-12-22 15:33:00
 * @modify date 2023-04-24 08:02:08
 * @desc [description]
 */


###############################################################################
## Create a Resource Group
##
## Gets reference to an existing resource group, specified in terraform.tfvars
###############################################################################
data "ibm_resource_group" "resource_group" {
   name   = var.resource_group
}


###############################################################################
## Transit Gateway
## If the intention is to interconnect this VSI with another VPC, Direct Link,
## IBM Cloud account, or PowerVS workspace, you will need a Transit Gateway
###############################################################################
resource "ibm_tg_gateway" "transit_gateway"{
  name  = join ("-", [var.prefix, "transit-gateway"])
  location=var.region
  global=false
  resource_group=data.ibm_resource_group.resource_group.id
}

resource "ibm_tg_connection" "ibm_tg_connection_1" {
  gateway      = ibm_tg_gateway.transit_gateway.id
  network_type = var.transit_gateway_connection_network_type_1
  name         = var.transit_gateway_connection_name_1
  network_id   = var.transit_gateway_connection_network_id_1
}

resource "ibm_tg_connection" "ibm_tg_connection_2" {
  gateway      = ibm_tg_gateway.transit_gateway.id
  network_type = var.transit_gateway_connection_network_type_2
  name         = var.transit_gateway_connection_name_2
  network_id   = var.transit_gateway_connection_network_id_2
}
