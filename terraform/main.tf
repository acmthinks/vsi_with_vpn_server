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
## This calls a module that takes a naming "prefix" and appends "-rg" to a
## Resource Group
## This Resource Group is referred to in this script as module.resource_group
###############################################################################
module "resource_group" {
  source = "./modules/resource-group"

  region           = var.region
  ibmcloud_api_key = var.ibmcloud_api_key
  prefix           = var.prefix
}



###############################################################################
## Create a VPC on IBM Cloud
## Availability Zones: 1 (no need for failover in Dev)
## Name: edge-vpc
## IP Address Range: 10.10.10.0/24 (256 IP addresses across all subnets)
###############################################################################
module "edge_vpc" {
  source = "./modules/vpc"

  region           = var.region
  ibmcloud_api_key = var.ibmcloud_api_key
  basename         = join("-", [var.prefix, "edge"])
  resource_group_id= module.resource_group.id
}

resource "ibm_is_vpc_address_prefix" "edge_prefix" {
  name = "edge-address-prefix"
  zone = var.zone
  vpc  = module.edge_vpc.vpc_id
  cidr = var.edge_vpc_address_prefix
}

###############################################################################
## Create Subnet #1: VPN Server Subnet
## Name: vpn-server-subnet
## CIDR: 10.10.10.0/25 (128 IP addresses in the VPN Server subnet)
## Language: Terraform
###############################################################################
resource "ibm_is_subnet" "vpn_server_subnet" {
  depends_on = [
    ibm_is_vpc_address_prefix.edge_prefix
  ]
  ipv4_cidr_block = var.edge_vpc_vpn_cidr
  name            = "vpn-server-subnet"
  vpc             = module.edge_vpc.vpc_id
  zone            = var.zone
  resource_group = module.resource_group.id
}

###############################################################################
## Create Subnet #2: VPN Destination Subnet
## Name: vpn-destination-subnet
## CIDR: 10.10.10.128/25 (128 IP addresses in the VPN Destination subnet)
###############################################################################
resource "ibm_is_subnet" "bastion_subnet" {
  depends_on = [
    ibm_is_vpc_address_prefix.edge_prefix
  ]
  ipv4_cidr_block = var.edge_vpc_bastion_cidr
  name            = "bastion-server-subnet"
  vpc             = module.edge_vpc.vpc_id
  zone            = var.zone
  resource_group = module.resource_group.id
}

###############################################################################
## Create NACL for Subnet #1
## Name: vpn-server-subnet-acl
## Rules:
##  #   | Direction | Action    | Protocol  | Source        | Destination
##  1   | inbound   | Allow     | UDP       | 0.0.0.0/0 any | 10.10.10.0/25 443
##  2   | inbound   | Allow     | ALL       | 10.10.10.0/24 | 192.168.0.0/16
##
##  1   | outbound  | Allow     | UDP       | 10.10.10.0/25 443 | 0.0.0.0/0 any
##  2   | outbound  | Allow     | ALL       | 192.168.0.0/16 | 10.10.10.0/24
###############################################################################
resource "ibm_is_network_acl" "vpn_server_subnet_acl" {
  name = "vpn-server-subnet-acl"
  vpc  = module.edge_vpc.vpc_id
  resource_group = module.resource_group.id
  rules {
    name        = "inbound-allow-same-subnet-ssh"
    action      = "allow"
    source      = "0.0.0.0/0"
    destination = var.edge_vpc_vpn_cidr
    direction   = "inbound"
    udp {
      port_max = 443
      port_min = 443
    }
  }
  rules {
    name        = "inbound-allow-vpc-to-public-all"
    action      = "allow"
    source      = var.edge_vpc_address_prefix
    destination = "192.168.0.0/16"
    direction   = "inbound"
  }
  rules {
    name        = "oubbound-allow-same-subnet-ssh"
    action      = "allow"
    source      = var.edge_vpc_vpn_cidr
    destination = "0.0.0.0/0"
    direction   = "outbound"
    udp {
      source_port_max = 443
      source_port_min = 443
    }
  }
  rules {
    name        = "outbound-allow-public-to-vpc"
    action      = "allow"
    source      = "192.168.0.0/16"
    destination = var.edge_vpc_address_prefix
    direction   = "outbound"
  }
}

###############################################################################
## Attach the NACL to the VPN Server subnet
###############################################################################
resource "ibm_is_subnet_network_acl_attachment" "vpn_server_subnet_acl_attachment" {
  subnet      = ibm_is_subnet.vpn_server_subnet.id
  network_acl = ibm_is_network_acl.vpn_server_subnet_acl.id
}


###############################################################################
## Create NACL for Subnet #2
## Name: bastion-server-subnet-acl
## Rules:
##  #   | Direction | Action    | Protocol  | Source        | Destination
##  1   | inbound   | Allow     | ALL       | 192.168.0.0/16| 10.10.10.128/25
##  2   | inbound   | Allow     | ALL       | 10.10.10.0/25 | 10.10.10.128/25
##
##  1   | outbound  | Allow     | ALL       | 0.0.0.0/0     | 0.0.0.0/0
##  2   | outbound  | Allow     | ALL       | 10.10.10.128/25 | 10.10.10.0/25
###############################################################################
resource "ibm_is_network_acl" "bastion_server_subnet_acl" {
  name = "bastion-server-subnet-acl"
  vpc  = module.edge_vpc.vpc_id
  resource_group = module.resource_group.id
  rules {
    name        = "inbound-public-allow-all"
    action      = "allow"
    source      = "192.168.0.0/16"
    destination = var.edge_vpc_bastion_cidr
    direction   = "inbound"
  }
  rules {
    name        = "inbound-allow-same-subnet-to-vpn"
    action      = "allow"
    source      = var.edge_vpc_vpn_cidr
    destination = var.edge_vpc_bastion_cidr
    direction   = "inbound"
  }
    rules {
    name        = "oubbound-allow-all"
    action      = "allow"
    source      = var.edge_vpc_bastion_cidr
    destination = "192.168.0.0/16"
    direction   = "outbound"
  }
   rules {
    name        = "outbound-allow-same-subnet-to-vpn"
    action      = "allow"
    source      = var.edge_vpc_bastion_cidr
    destination = var.edge_vpc_vpn_cidr
    direction   = "outbound"
  }
  rules {
    name        = "outbound-allow-same-subnet-to-any"
    action      = "allow"
    source      = var.edge_vpc_bastion_cidr
    destination = "0.0.0.0/0"
    direction   = "outbound"
    tcp {
      source_port_min = 443
      source_port_max = 443
    }
  }
}

###############################################################################
## Attach the NACL to the Bastion Server subnet
###############################################################################
resource "ibm_is_subnet_network_acl_attachment" "bastion_server_subnet_acl_attachment" {
  subnet      = ibm_is_subnet.bastion_subnet.id
  network_acl = ibm_is_network_acl.bastion_server_subnet_acl.id
}


###############################################################################
## Create Securia public gateway for VPN Server subnet
## Name: vpn-server-public-gateway
###############################################################################
#resource "ibm_is_public_gateway" "vpn_server_public_gateway" {
#  name = "vpn-server-public-gateway"
#  vpc  = module.edge_vpc.vpc_id
#  zone = var.zone
#}

###############################################################################
## Attach the public gateway to the VPN Server subnet
###############################################################################
#resource "ibm_is_subnet_public_gateway_attachment" "vpn_server_public_gateway_attachment" {
#  subnet                = ibm_is_subnet.vpn_server_subnet.id
#  public_gateway         = ibm_is_public_gateway.vpn_server_public_gateway.id
#}



###############################################################################
## Create Security Group for VPN Server
## Name: vpn-server-sg
## Rules:
##  Direction | Protocol  | Source Type | Source
##  inbound   | UDP       | Any         | 0.0.0.0/0 443
##  inbound   | ALL       | CIDR block  | 10.10.10.0/24
##
##  Direction | Protocol  | Dest Type   | Destination
##  egress    | UDP       | Any         | 0.0.0.0/0 443
##  egress    | ALL       | CIDR block  | 10.10.10.0/24
###############################################################################
resource "ibm_is_security_group" "vpn_server_sg" {
  name = "vpn-server-sg"
  vpc = module.edge_vpc.vpc_id
  resource_group = module.resource_group.id
}

resource "ibm_is_security_group_rule" "vpn_server_rule_1" {
  group = ibm_is_security_group.vpn_server_sg.id
  direction = "inbound"
  remote = "0.0.0.0/0"
  udp {
    port_min = 443
    port_max = 443
  }
}

resource "ibm_is_security_group_rule" "vpn_server_rule_2" {
  group = ibm_is_security_group.vpn_server_sg.id
  direction = "inbound"
  remote = var.edge_vpc_address_prefix
}

resource "ibm_is_security_group_rule" "vpn_server_rule_3" {
  group = ibm_is_security_group.vpn_server_sg.id
  direction = "outbound"
  remote = "0.0.0.0/0"
  udp {
    port_min = 443
    port_max = 443
  }
}

resource "ibm_is_security_group_rule" "vpn_server_rule_4" {
  group = ibm_is_security_group.vpn_server_sg.id
  direction = "outbound"
  remote = var.edge_vpc_address_prefix
}


###############################################################################
## Create Security Group for Bastion Server
## Name: bastion-sg
## Rules:
##  Direction | Protocol  | Source Type   | Source
##  inbound   | ALL       | CIDR block    | 10.10.10.0/25
##  inbound   | ICMP      | CIDR block    | 10.10.10.0/24   [Type:8, Code:Any]
##  inbound   | TCP       | CIDR block    | 10.10.10.0/24   [Ports 22-22]
##  inbound   | ALL       | CIDR block    | 192.168.0.0/16
##
##  Direction | Protocol  | Dest Type   | Destination
##  egress    | ALL       | CIDR block    | 10.10.10.0/25
##  egress    | ICMP      | CIDR block    | 10.10.10.0/24   [Type:8, Code:Any]
##  egress    | TCP       | CIDR block    | 10.10.10.0/24   [Ports 22-22]
##  egress    | ALL       | CIDR block    | 192.168.0.0/16
###############################################################################
resource "ibm_is_security_group" "bastion_server_sg" {
  name = "bastion-server-sg"
  vpc = module.edge_vpc.vpc_id
  resource_group = module.resource_group.id
}

resource "ibm_is_security_group_rule" "bastion_server_rule_1" {
  group = ibm_is_security_group.bastion_server_sg.id
  direction = "inbound"
  remote = var.edge_vpc_vpn_cidr
}

resource "ibm_is_security_group_rule" "bastion_server_rule_2" {
  group = ibm_is_security_group.bastion_server_sg.id
  direction = "inbound"
  remote = var.edge_vpc_address_prefix
  icmp {
    type = 8
  }
}

resource "ibm_is_security_group_rule" "bastion_server_rule_3" {
  group = ibm_is_security_group.bastion_server_sg.id
  direction = "inbound"
  remote = var.edge_vpc_address_prefix
  tcp {
    port_min = 22
    port_max = 22
  }
}

resource "ibm_is_security_group_rule" "bastion_server_rule_4" {
  group = ibm_is_security_group.bastion_server_sg.id
  direction = "inbound"
  remote = "192.168.0.0/16"
}

resource "ibm_is_security_group_rule" "bastion_server_rule_5" {
  group = ibm_is_security_group.bastion_server_sg.id
  direction = "outbound"
  remote = var.edge_vpc_vpn_cidr
}

resource "ibm_is_security_group_rule" "bastion_server_rule_6" {
  group = ibm_is_security_group.bastion_server_sg.id
  direction = "outbound"
  remote = var.edge_vpc_address_prefix
  icmp {
    type = 8
  }
}

resource "ibm_is_security_group_rule" "bastion_server_rule_7" {
  group = ibm_is_security_group.bastion_server_sg.id
  direction = "outbound"
  remote = var.edge_vpc_address_prefix
  tcp {
    port_min = 22
    port_max = 22
  }
}

resource "ibm_is_security_group_rule" "bastion_server_rule_8" {
  group = ibm_is_security_group.bastion_server_sg.id
  direction = "outbound"
  remote = "192.168.0.0/16"
}

##create secrets manager
#resource "ibm_resource_instance" "secrets_manager" {
#  name = "secrets-manager"
#  service = join("-", [var.prefix, "secrets-manager"])
#  plan = "standard"
#  location = "us-south"
#  resource_group_id = module.resource_group.id
#}

data "ibm_resource_instance" "secrets_manager" {
  identifier = var.secrets_manager_instance_crn
}

data "ibm_sm_imported_certificate" "imported_vpn_certificate" {
  instance_id   = data.ibm_resource_instance.secrets_manager.guid
  region        = var.region
  name          = "qroc-vpn-server-cert"
  secret_group_name = "vpn-ca-certificates"
  #secret_id = "fed1412c-97f1-1449-8426-7137a7571ce8"
}

data "ibm_sm_arbitrary_secret" "ssh_key_secret" {
  instance_id   = data.ibm_resource_instance.secrets_manager.guid
  region        = var.region
  name          = "andrea-ssh-public-key"
  secret_group_name = "public-ssh-keys"
  #secret_id = "4d83c74c-1bc8-c167-bd32-428e5b38bba3"
}

##create secrets manager group
##resource "ibm_sm_secret_group" "secrets_manager_group"{
#  instance_id   = data.ibm_resource_instance.secrets_manager.id
#  region        = var.region
#  name          = "vpn-server-certificates"
#  description = "Used to store certificates for the VPN Server"
#}

##create a vpn server certificate
## create a vpn client cert authority

resource "ibm_is_vpn_server" "vpn_server" {
  certificate_crn = data.ibm_sm_imported_certificate.imported_vpn_certificate.crn
  client_authentication {
    method    = "certificate"
    client_ca_crn = data.ibm_sm_imported_certificate.imported_vpn_certificate.crn
  }
  client_ip_pool         = "192.168.0.0/16"
  client_idle_timeout    = 600
  enable_split_tunneling = true
  name                   = join("-", [var.prefix, "vpn-server"])
  port                   = 443
  protocol               = "udp"
  subnets                = [ibm_is_subnet.vpn_server_subnet.id]
  resource_group = module.resource_group.id
  security_groups = [ibm_is_security_group.vpn_server_sg.id]
}

## VPN Server route
resource "ibm_is_vpn_server_route" "vpn_server_route" {
  vpn_server    = ibm_is_vpn_server.vpn_server.vpn_server
  destination   = var.edge_vpc_bastion_cidr
  action        = "deliver"
  name          = "deliver-bastion-host"
}


### Create Bastion
data "ibm_is_ssh_key" "bastion_ssh_key" {
  name       = "andrea-ssh-key"
}

# get catalog image
data "ibm_is_image" "centos" {
  name = "ibm-centos-stream-9-amd64-7"
}

resource "ibm_is_instance" "bastion_server_vsi" {
  name    = "bastion-server-vsi"
  image   = data.ibm_is_image.centos.id
  profile = "bx2-2x8"

  primary_network_interface {
    subnet = ibm_is_subnet.bastion_subnet.id
    security_groups = [ibm_is_security_group.bastion_server_sg.id]
  }

  vpc  = module.edge_vpc.vpc_id
  zone = var.zone
  #resource_group = module.resource_group.id
  keys = [data.ibm_is_ssh_key.bastion_ssh_key.id]
}




##########
#Transit Gateway
resource "ibm_tg_gateway" "transit_gateway"{
  name="powervs-transit-gateway"
  location=var.region
  global=false
  resource_group=module.resource_group.id
}

### TG Connection
resource "ibm_tg_connection" "test_ibm_tg_connection" {
  gateway      = ibm_tg_gateway.transit_gateway.id
  network_type = "power_virtual_server"
  name         = "powervs-per-connection"
  network_id   = var.powervs_workspace_crn
}
