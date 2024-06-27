output "vpc_id" {
  value = ibm_is_vpc.vpc.id
}

output "default_security_group_id" {
  value = ibm_is_vpc.vpc.default_security_group
}