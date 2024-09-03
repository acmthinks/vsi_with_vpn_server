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
## Create a VPC on IBM Cloud
## Availability Zones: 1 (no need for failover in Dev)
## Name: edge-vpc
## IP Address Range: 10.10.10.0/24 (256 IP addresses across all subnets)
###############################################################################
resource "ibm_is_vpc" "edge_vpc" {
  name = join("-", [var.prefix, "edge-vpc"])
  resource_group = data.ibm_resource_group.resource_group.id
  address_prefix_management = "manual"
  default_routing_table_name = join("-", [var.prefix, "edge-vpc", "rt", "default"])
  default_security_group_name = join("-", [var.prefix, "edge-vpc", "sg", "default"])
  default_network_acl_name = join("-", [var.prefix, "edge-vpc", "acl", "default"])
}

#set VPC Address prefix (all subnets in this vpc will derive from this range)
resource "ibm_is_vpc_address_prefix" "edge_prefix" {
  name = "edge-address-prefix"
  zone = var.zone
  vpc  = ibm_is_vpc.edge_vpc.id
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
  vpc             = ibm_is_vpc.edge_vpc.id
  zone            = var.zone
  resource_group = data.ibm_resource_group.resource_group.id
}

###############################################################################
## Create Subnet #2: Bastion Subnet
## Name: bastion-server-subnet
## CIDR: 10.10.10.128/25 (128 IP addresses in the VPN Destination subnet)
###############################################################################
resource "ibm_is_subnet" "bastion_subnet" {
  depends_on = [
    ibm_is_vpc_address_prefix.edge_prefix
  ]
  ipv4_cidr_block = var.edge_vpc_bastion_cidr
  name            = "bastion-server-subnet"
  vpc             = ibm_is_vpc.edge_vpc.id
  zone            = var.zone
  resource_group = data.ibm_resource_group.resource_group.id
}

###############################################################################
## Create NACL for Subnet #1
## Name: vpn-server-subnet-acl
## Rules:
##  #   | Direction | Action    | Protocol  | Source        | Destination
##  1   | inbound   | Allow     | UDP       | 0.0.0.0/0 any | 10.50.0.0/25 443
##  2   | inbound   | Allow     | ALL       | 10.50.0.0/24  | 192.168.0.0/16
##  3   | inbound   | Deny      | ALL       | 0.0.0.0/0 any | 0.0.0.0/0 any
##
##  1   | outbound  | Allow     | UDP       | 10.50.0.0/25 443 | 0.0.0.0/0 any
##  2   | outbound  | Allow     | ALL       | 192.168.0.0/16 | 10.50.0.0/24
##  3   | outbound  | Deny      | ALL       | 0.0.0.0/0 any | 0.0.0.0/0 any
###############################################################################
resource "ibm_is_network_acl" "vpn_server_subnet_acl" {
  name = "vpn-server-subnet-acl"
  vpc  = ibm_is_vpc.edge_vpc.id
  resource_group = data.ibm_resource_group.resource_group.id
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
    destination = var.edge_vpc_public_cidr
    direction   = "inbound"
  }
    rules {
    name        = "inbound-deny-all"
    action      = "deny"
    source      = "0.0.0.0/0"
    destination = "0.0.0.0/0"
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
    source      = var.edge_vpc_public_cidr
    destination = var.edge_vpc_address_prefix
    direction   = "outbound"
  }
  rules {
    name        = "outbound-deny-all"
    action      = "deny"
    source      = "0.0.0.0/0"
    destination = "0.0.0.0/0"
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
##  1   | inbound   | Allow     | ALL       | 192.168.0.0/16| 10.50.0.128/25 Internet traffic through Client VPN Server
##  2   | inbound   | Allow     | ALL       | 10.50.0.0/25  | 10.50.0.128/25
##  (3) | inbound   | Allow     | ALL       | 10.60.0.128/25| 10.50.0.128/25 for connecting to another VPC or PowerVS workspace
##  (4) | inbound   | Allow     | ALL       | 161.26.0.0/16 | 0.0.0.0/0 IaaS service endpoints (RHN, NTP, DNS, et al)
##  (5) | inbound   | Allow     | TCP       | 166.9.228.45/32 6443 | 10.50.0.128/25  wpp1 collection endpoint
##  (7) | inbound   | Allow     | TCP       | 166.9.229.45/32 6443 | 10.50.0.128/25  wpp2 collection endpoint
##  (8) | inbound   | Allow     | TCP       | 166.9.230.45/32 6443 | 10.50.0.128/25  wpp3 collection endpoint
##  (9) | inbound   | Allow     | TCP       | 166.9.14.170/32 6443 | 10.50.0.128/25  wpp1 collection endpoint (deprecated)
##  (10)| inbound   | Allow     | TCP       | 166.9.48.41/32 6443  | 10.50.0.128/25  wpp2 collection endpoint (deprecated)
##  (11)| inbound   | Allow     | TCP       | 166.9.17.11/32 6443  | 10.50.0.128/25  wpp3 collection endpoint (deprecated)
##  12  | inbound   | Deny      | ALL       | 0.0.0.0/0     | 10.50.0.128/25
##
##  1   | outbound  | Allow     | ALL       | 10.50.0.128/25 | 192.168.0.0/16 Internet traffic through Client VPN Server
##  2   | outbound  | Allow     | ALL       | 10.50.0.128/25 | 10.50.0.0/25
##  3   | outbound  | Allow     | TCP       | 10.50.0.128/25 443 | 0.0.0.0/0
##  (4) | outbound  | Allow     | ALL       | 10.50.0.128/25 | 10.60.0.128/25 for connecting to another VPC or PowerVS workspace
##  (5) | outbound  | Allow     | ALL       | 10.50.0.128/25      | 161.26.0.0/16 IaaS service endpoints (RHN, NTP, DNS, et al)
##  (6) | outbound  | Allow     | TCP       | 10.50.0.128/25      | 166.9.228.45/32 6443   wpp1 collection endpoint
##  (7) | outbound  | Allow     | TCP       | 10.50.0.128/25      | 166.9.229.45/32 6443   wpp2 collection endpoint
##  (8) | outbound  | Allow     | TCP       | 10.50.0.128/25      | 166.9.230.45/32 6443   wpp3 collection endpoint
##  (9) | outbound  | Allow     | TCP       | 10.50.0.128/25      | 166.9.14.170/32 6443   wpp1 collection endpoint (deprecated)
##  (10)| outbound  | Allow     | TCP       | 10.50.0.128/25      | 166.9.48.41/32 6443   wpp2 collection endpoint (deprecated)
##  (11)| outbound  | Allow     | TCP       | 10.50.0.128/25      | 166.9.17.11/32 6443   wpp3 collection endpoint (deprecated)
##  12  | outbound  | Deny      | ALL       | 10.50.0.128/25     | 0.0.0.0/0
###############################################################################
resource "ibm_is_network_acl" "bastion_server_subnet_acl" {
  name = "bastion-server-subnet-acl"
  vpc  = ibm_is_vpc.edge_vpc.id
  resource_group = data.ibm_resource_group.resource_group.id
  rules {
    name        = "inbound-public-allow-all"
    action      = "allow"
    source      = var.edge_vpc_public_cidr
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
    name        = "inbound-iaas-service-endpoints"
    action      = "allow"
    source      = var.iaas-service-endpoint-cidr
    destination = "0.0.0.0/0"
    direction   = "inbound"
  }
  rules {
    name        = "inbound-wpp1-agent"
    action      = "allow"
    source      = var.wpp-collection-endpoint-cidr-1
    destination = var.edge_vpc_bastion_cidr
    direction   = "inbound"
    tcp {
      source_port_min = var.wpp-collection-endpoint-port
      source_port_max = var.wpp-collection-endpoint-port
    }
  }
  rules {
    name        = "inbound-wpp2-agent"
    action      = "allow"
    source      = var.wpp-collection-endpoint-cidr-2
    destination = var.edge_vpc_bastion_cidr
    direction   = "inbound"
    tcp {
      source_port_min = var.wpp-collection-endpoint-port
      source_port_max = var.wpp-collection-endpoint-port
    }
  }
  rules {
    name        = "inbound-wpp3-agent"
    action      = "allow"
    source      = var.wpp-collection-endpoint-cidr-3
    destination = var.edge_vpc_bastion_cidr
    direction   = "inbound"
    tcp {
      source_port_min = var.wpp-collection-endpoint-port
      source_port_max = var.wpp-collection-endpoint-port
    }
  }
  rules {
    name        = "inbound-wpp1-agent-deprecated"
    action      = "allow"
    source      = var.wpp-collection-endpoint-cidr-1-deprecated
    destination = var.edge_vpc_bastion_cidr
    direction   = "inbound"
    tcp {
      source_port_min = var.wpp-collection-endpoint-port
      source_port_max = var.wpp-collection-endpoint-port
    }
  }
  rules {
    name        = "inbound-wpp2-agent-deprecated"
    action      = "allow"
    source      = var.wpp-collection-endpoint-cidr-2-deprecated
    destination = var.edge_vpc_bastion_cidr
    direction   = "inbound"
    tcp {
      source_port_min = var.wpp-collection-endpoint-port
      source_port_max = var.wpp-collection-endpoint-port
    }
  }
  rules {
    name        = "inbound-wpp3-agent-deprecated"
    action      = "allow"
    source      = var.wpp-collection-endpoint-cidr-3-deprecated
    destination = var.edge_vpc_bastion_cidr
    direction   = "inbound"
    tcp {
      source_port_min = var.wpp-collection-endpoint-port
      source_port_max = var.wpp-collection-endpoint-port
    }
  }
  rules {
    name        = "inbound-deny-all"
    action      = "deny"
    source      = "0.0.0.0/0"
    destination = var.edge_vpc_bastion_cidr
    direction   = "inbound"
  }
    rules {
    name        = "oubbound-allow-all"
    action      = "allow"
    source      = var.edge_vpc_bastion_cidr
    destination = var.edge_vpc_public_cidr
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
  rules {
    name        = "outbound-iaas-service-endpoints"
    action      = "allow"
    source      = var.edge_vpc_bastion_cidr
    destination = var.iaas-service-endpoint-cidr
    direction   = "outbound"
  }
  rules {
    name        = "outbound-wpp1-agent"
    action      = "allow"
    source      = var.edge_vpc_bastion_cidr
    destination = var.wpp-collection-endpoint-cidr-1
    direction   = "outbound"
    tcp {
      port_min = var.wpp-collection-endpoint-port
      port_max = var.wpp-collection-endpoint-port
    }
  }
  rules {
    name        = "outbound-wpp2-agent"
    action      = "allow"
    source      = var.edge_vpc_bastion_cidr
    destination = var.wpp-collection-endpoint-cidr-2
    direction   = "outbound"
    tcp {
      port_min = var.wpp-collection-endpoint-port
      port_max = var.wpp-collection-endpoint-port
    }
  }
  rules {
    name        = "outbound-wpp3-agent"
    action      = "allow"
    source      = var.edge_vpc_bastion_cidr
    destination = var.wpp-collection-endpoint-cidr-3
    direction   = "outbound"
    tcp {
      port_min = var.wpp-collection-endpoint-port
      port_max = var.wpp-collection-endpoint-port
    }
  }
  rules {
    name        = "outbound-wpp1-agent-deprecated"
    action      = "allow"
    source      = var.edge_vpc_bastion_cidr
    destination = var.wpp-collection-endpoint-cidr-1-deprecated
    direction   = "outbound"
    tcp {
      port_min = var.wpp-collection-endpoint-port
      port_max = var.wpp-collection-endpoint-port
    }
  }
  rules {
    name        = "outbound-wpp2-agent-deprecated"
    action      = "allow"
    source      = var.edge_vpc_bastion_cidr
    destination = var.wpp-collection-endpoint-cidr-2-deprecated
    direction   = "outbound"
    tcp {
      port_min = var.wpp-collection-endpoint-port
      port_max = var.wpp-collection-endpoint-port
    }
  }
  rules {
    name        = "outbound-wpp3-agent-deprecated"
    action      = "allow"
    source      = var.edge_vpc_bastion_cidr
    destination = var.wpp-collection-endpoint-cidr-3-deprecated
    direction   = "outbound"
    tcp {
      port_min = var.wpp-collection-endpoint-port
      port_max = var.wpp-collection-endpoint-port
    }
  }
  rules {
    name        = "outbound-deny-all"
    action      = "deny"
    source      = var.edge_vpc_bastion_cidr
    destination = "0.0.0.0/0"
    direction   = "outbound"
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
## Create Security Group for VPN Server
## Name: vpn-server-sg
## Rules:
##  Direction | Protocol  | Source Type | Source        | Destination
##  inbound   | UDP       | Any         | 0.0.0.0/0     | 0.0.0.0/0 443
##  inbound   | ALL       | CIDR block  | 10.50.0.0/24  | 0.0.0.0/0
##
##  Direction | Protocol  | Source Type | Source        | Destination
##  egress    | UDP       | Any         | 0.0.0.0/0     | 0.0.0.0/0 443
##  egress    | ALL       | CIDR block  | 0.0.0.0/0     | 10.50.0.0/24
###############################################################################
resource "ibm_is_security_group" "vpn_server_sg" {
  name = "vpn-server-sg"
  vpc = ibm_is_vpc.edge_vpc.id
  resource_group = data.ibm_resource_group.resource_group.id
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
##  Direction | Protocol  | Source          | Destination
##  inbound   | ALL       | 192.168.0.0/16  | 0.0.0.0/0
##  inbound   | TCP       | 10.50.0.0/24    | 0.0.0.0/0 [Ports 22-22]
##  inbound   | ICMP      | 10.10.10.0/24   | 0.0.0.0/0 [Type:8, Code:Any]
##  inbound   | ALL       | 10.50.0.0/25    | 0.0.0.0/0
##  inbound   | ALL       | 161.26.0.0/16    | 0.0.0.0/0
##  (inbound) | ALL       | 10.60.0.128/25  | 0.0.0.0/0 for connecting to another VPC or PowerVS workspace

##
##  Direction | Protocol  | Source          | Destination
##  egress    | ALL       | 0.0.0.0/0       | 192.168.0.0/16
##  egress    | TCP       | 0.0.0.0/0       | 10.50.0.0/24   [Ports 22-22]
##  egress    | ICMP      | 0.0.0.0/0       | 10.50.0.0/24 [Type:8, Code:Any]
##  egress    | ALL       | 0.0.0.0/0       | 10.50.0.0/25
##  egress    | ALL       | 0.0.0.0/0       | 161.26.0.0/16
##  (egress)  | ALL       | 0.0.0.0/0       | 10.60.0.128/25  for connecting to another VPC or PowerVS workspace
###############################################################################
resource "ibm_is_security_group" "bastion_server_sg" {
  name = "bastion-server-sg"
  vpc = ibm_is_vpc.edge_vpc.id
  resource_group = data.ibm_resource_group.resource_group.id
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
  remote = var.edge_vpc_public_cidr
}

resource "ibm_is_security_group_rule" "bastion_server_rule_inbound_iaas_endpoints" {
  group = ibm_is_security_group.bastion_server_sg.id
  direction = "inbound"
  remote = var.iaas-service-endpoint-cidr
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
  remote = var.edge_vpc_public_cidr
}

resource "ibm_is_security_group_rule" "bastion_server_rule_outbound_iaas_endpoints" {
  group = ibm_is_security_group.bastion_server_sg.id
  direction = "outbound"
  remote = var.iaas-service-endpoint-cidr
}

###############################################################################
## Create Security Group for IBM Cloud Security & Compliance Center - WPP
## Name: scc-wpp-sg
## Rules:
##  Direction | Protocol  | Source          | Destination
##  inbound   | TCP       | 166.9.228.45/32 | 0.0.0.0/0 [Ports 6443-6443]
##  inbound   | TCP       | 166.9.229.45/32 | 0.0.0.0/0 [Ports 6443-6443]
##  inbound   | TCP       | 166.9.230.45/32 | 0.0.0.0/0 [Ports 6443-6443]
##  inbound   | TCP       | 166.9.14.170/32 | 0.0.0.0/0 [Ports 6443-6443]
##  inbound   | TCP       | 166.9.48.41/32  | 0.0.0.0/0 [Ports 6443-6443]
##  inbound   | TCP       | 166.9.17.11/32  | 0.0.0.0/0 [Ports 6443-6443]

##
##  Direction | Protocol  | Source          | Destination
##  outbound  | TCP       | 0.0.0.0/0       | 166.9.228.45/32 Ports 6443-6443]
##  outbound  | TCP       | 0.0.0.0/0       | 166.9.229.45/32 [Ports 6443-6443]
##  outbound  | TCP       | 0.0.0.0/0       | 166.9.230.45/32 [Ports 6443-6443]
##  outbound  | TCP       | 0.0.0.0/0       | 166.9.14.170/32 [Ports 6443-6443]
##  outbound  | TCP       | 0.0.0.0/0       | 166.9.48.41/32  [Ports 6443-6443]
##  outbound  | TCP       | 0.0.0.0/0       | 166.9.17.11/32  [Ports 6443-6443]
###############################################################################
resource "ibm_is_security_group" "scc_wcc_sg" {
  name = "scc-wcc-sg"
  vpc = ibm_is_vpc.edge_vpc.id
  resource_group = data.ibm_resource_group.resource_group.id
}
resource "ibm_is_security_group_rule" "scc_wpp_rule_1" {
  group = ibm_is_security_group.scc_wcc_sg.id
  direction = "inbound"
  remote = var.wpp-collection-endpoint-cidr-1
  tcp {
    port_min = 6443
    port_max = 6443
  }
}
resource "ibm_is_security_group_rule" "scc_wpp_rule_2" {
  group = ibm_is_security_group.scc_wcc_sg.id
  direction = "inbound"
  remote = var.wpp-collection-endpoint-cidr-2
  tcp {
    port_min = 6443
    port_max = 6443
  }
}
resource "ibm_is_security_group_rule" "scc_wpp_rule_3" {
  group = ibm_is_security_group.scc_wcc_sg.id
  direction = "inbound"
  remote = var.wpp-collection-endpoint-cidr-3
  tcp {
    port_min = 6443
    port_max = 6443
  }
}
resource "ibm_is_security_group_rule" "scc_wpp_rule_4" {
  group = ibm_is_security_group.scc_wcc_sg.id
  direction = "inbound"
  remote = var.wpp-collection-endpoint-cidr-1-deprecated
  tcp {
    port_min = 6443
    port_max = 6443
  }
}
resource "ibm_is_security_group_rule" "scc_wpp_rule_5" {
  group = ibm_is_security_group.scc_wcc_sg.id
  direction = "inbound"
  remote = var.wpp-collection-endpoint-cidr-2-deprecated
  tcp {
    port_min = 6443
    port_max = 6443
  }
}
resource "ibm_is_security_group_rule" "scc_wpp_rule_6" {
  group = ibm_is_security_group.scc_wcc_sg.id
  direction = "inbound"
  remote = var.wpp-collection-endpoint-cidr-3-deprecated
  tcp {
    port_min = 6443
    port_max = 6443
  }
}
resource "ibm_is_security_group_rule" "scc_wpp_rule_7" {
  group = ibm_is_security_group.scc_wcc_sg.id
  direction = "outbound"
  remote = var.wpp-collection-endpoint-cidr-1
  tcp {
    port_min = 6443
    port_max = 6443
  }
}
resource "ibm_is_security_group_rule" "scc_wpp_rule_8" {
  group = ibm_is_security_group.scc_wcc_sg.id
  direction = "outbound"
  remote = var.wpp-collection-endpoint-cidr-2
  tcp {
    port_min = 6443
    port_max = 6443
  }
}
resource "ibm_is_security_group_rule" "scc_wpp_rule_9" {
  group = ibm_is_security_group.scc_wcc_sg.id
  direction = "outbound"
  remote = var.wpp-collection-endpoint-cidr-3
  tcp {
    port_min = 6443
    port_max = 6443
  }
}
resource "ibm_is_security_group_rule" "scc_wpp_rule_10" {
  group = ibm_is_security_group.scc_wcc_sg.id
  direction = "outbound"
  remote = var.wpp-collection-endpoint-cidr-1-deprecated
  tcp {
    port_min = 6443
    port_max = 6443
  }
}
resource "ibm_is_security_group_rule" "scc_wpp_rule_11" {
  group = ibm_is_security_group.scc_wcc_sg.id
  direction = "outbound"
  remote = var.wpp-collection-endpoint-cidr-2-deprecated
  tcp {
    port_min = 6443
    port_max = 6443
  }
}
resource "ibm_is_security_group_rule" "scc_wpp_rule_12" {
  group = ibm_is_security_group.scc_wcc_sg.id
  direction = "outbound"
  remote = var.wpp-collection-endpoint-cidr-3-deprecated
  tcp {
    port_min = 6443
    port_max = 6443
  }
}


## Get Secrets Manager instance
data "ibm_resource_instance" "secrets_manager" {
  identifier = var.secrets_manager_instance_crn
}
# Get vpn server cert (stored in Secrets Manager)
data "ibm_sm_imported_certificate" "imported_vpn_certificate" {
  instance_id   = data.ibm_resource_instance.secrets_manager.guid
  region        = var.region
  name          = "vpn-server-cert"
  secret_group_name = "vpn-ca-certificates"
  #secret_id = "fed1412c-97f1-1449-8426-7137a7571ce8"
}
## get public ssh key (stored in Secrets Manager)
data "ibm_sm_arbitrary_secret" "ssh_key_secret" {
  instance_id   = data.ibm_resource_instance.secrets_manager.guid
  region        = var.region
  name          = "andrea-ssh-public-key"
  secret_group_name = "public-ssh-keys"
  #secret_id = "4d83c74c-1bc8-c167-bd32-428e5b38bba3"
}

#create VSI
resource "ibm_is_vpn_server" "vpn_server" {
  certificate_crn = data.ibm_sm_imported_certificate.imported_vpn_certificate.crn
  client_authentication {
    method    = "certificate"
    client_ca_crn = data.ibm_sm_imported_certificate.imported_vpn_certificate.crn
  }
  client_ip_pool         = var.edge_vpc_public_cidr
  client_idle_timeout    = 600
  enable_split_tunneling = true
  name                   = join("-", [var.prefix, "vpn-server"])
  port                   = 443
  protocol               = "udp"
  subnets                = [ibm_is_subnet.vpn_server_subnet.id]
  resource_group = data.ibm_resource_group.resource_group.id
  security_groups = [ibm_is_security_group.vpn_server_sg.id]
}

## VPN Server route -- deliver all traffic to Bastion vsi
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

data "ibm_is_image" "debian" {
  name = "ibm-debian-12-6-minimal-amd64-1"
}

resource "ibm_is_virtual_network_interface" "bastion_server_vni" {
  name = "bastion-server-vni"
  resource_group = data.ibm_resource_group.resource_group.id
  allow_ip_spoofing = false
  enable_infrastructure_nat = true
  auto_delete = false
  subnet = ibm_is_subnet.bastion_subnet.id
  security_groups = [ibm_is_security_group.bastion_server_sg.id, ibm_is_security_group.scc_wcc_sg.id]
}

resource "ibm_is_instance" "bastion_server_vsi" {
  name    = "bastion-server-vsi"
  image   = data.ibm_is_image.debian.id
  profile = "bx2-2x8"

  boot_volume {
    name = "bastion-server-boot"
    auto_delete_volume = true
  }

  primary_network_attachment {
    name = "eth0"
    virtual_network_interface {
      id = ibm_is_virtual_network_interface.bastion_server_vni.id
    }
  }

  vpc  = ibm_is_vpc.edge_vpc.id
  zone = var.zone
  resource_group = data.ibm_resource_group.resource_group.id
  keys = [data.ibm_is_ssh_key.bastion_ssh_key.id]
  tags = ["scc-wpp"]
}

#Create a public gateway, but do not attach by default
# this can be used to get access to the Intenret to install agents
resource "ibm_is_public_gateway" "public_gateway" {
  name = "public-gateway"
  vpc = ibm_is_vpc.edge_vpc.id
  zone = var.zone
  resource_group = data.ibm_resource_group.resource_group.id
}

#resource "ibm_is_subnet_public_gateway_attachment" "public_gateway_attach"{
#  subnet = ibm_is_subnet.bastion_subnet.id
#  public_gateway = ibm_is_public_gateway.public_gateway.id
#}
