resource "ibm_is_vpc" "vpc" {
  name = "${var.basename}-vpc"
  resource_group = var.resource_group_id
  address_prefix_management = "manual"
  default_routing_table_name = join("-", [var.basename, "rt", "default"])
  default_security_group_name = join("-", [var.basename, "sg", "default"])
  default_network_acl_name = join("-", [var.basename, "acl", "default"])
}
