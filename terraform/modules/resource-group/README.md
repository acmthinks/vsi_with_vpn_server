# Create Resource Group

## Introduction
This example will create an IBM Cloud Resource Group, which is a fundamental construct to group cloud resources. Once a cloud resource is created in a Resource Group, it cannot be moved to another Resource Group. When creating cloud resources, the default Resource Group is `default`. This example is based off of the IBM Cloud docs, [Managing resource groups] (https://cloud.ibm.com/docs/account?topic=account-rgs&interface=terraform).


### Prerequisites

* Terraform 0.14 or higher
* IBM API Key


### Input Variables

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | -------- |
| ibmcloud_api_key | API Key used to provision resources.  Your key must be authorized to perform the actions in this script. | string | N/A | yes |
| region | IBM Cloud region. | string | us-south | yes |
| resource_group_id | The id of the resource group in which to provision all resources | string | N/A | yes |


### Output Variables

| Name | Description |
| ---- | ----------- |
| resource_group_id  | The name of the Resource Group created |

## Terraform Version
Tested with Terraform v0.13


## Running the configuration

Rename terraform.tfvars.template to terraform.tfvars and fill in all required variables

Then run:

```shell
terraform init
```

```shell
terraform apply
```
 
After the script finishes running, the Resource Group will be visible in the IBM Cloud console or via the IBM Cloud CLI.

