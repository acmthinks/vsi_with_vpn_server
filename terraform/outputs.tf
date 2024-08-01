output "vpn_server_url" {
    value = ibm_is_vpn_server.vpn_server.hostname
}

output "bastion_server_vsi_ip" {
    value = ibm_is_instance.bastion_server_vsi.primary_network_attachment[0].virtual_network_interface[0].primary_ip
    #value = ibm_is_instance.bastion_server_vsi.primary_network_attachment[0].virtual_network_interface[0].
}

output "vpc_name" {
    value = ibm_is_vpc.edge_vpc.name
}

output "vpc_crn" {
    value = ibm_is_vpc.edge_vpc.crn
}

output "message" {
    value = <<EOM
    1. Connect with OpenVPN. Be sure to download the client profile template (locally) and specify your certificate and private key.
    2. On local terminal type the following to access the bastion server:

    ssh -i <path_to_private_key> root@${ibm_is_instance.bastion_server_vsi.primary_network_interface[0].primary_ipv4_address}

    EOM
}
