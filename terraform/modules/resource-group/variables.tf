variable "ibmcloud_api_key" {
   description = "API Key or Service ID can be used"
}

variable "region" {
   default = "us-south"
   type = string
   description = "IBM Cloud region to run in."
}
 
variable "prefix" {
   default = "default"
   type = string
   description = "Prefix used to name all resources."
}
 