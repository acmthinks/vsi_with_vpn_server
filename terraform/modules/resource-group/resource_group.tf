#######################################################
# Create resource group for guild
#######################################################
resource "ibm_resource_group" "group" {
   name = join("-", [var.prefix,"rg"])
   tags = ["schematics"]
}

