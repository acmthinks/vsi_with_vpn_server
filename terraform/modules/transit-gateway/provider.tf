terraform {
  required_providers {
    ibm = {
      source = "IBM-Cloud/ibm"
      version = "1.66.0"
    }
  }
}
# Configure the IBM Provider
provider "ibm" {
  ibmcloud_api_key = var.ibmcloud_api_key
  region           = var.region
}
