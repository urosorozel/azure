variable "suffix_name" {
    description = "Suffix for resource names"
    default  = "project1"
    type = string
}

variable "vm_count" {
    description = "VM count"
    default  = 2
    type = number
}

variable "region_name" {
    description = "Azure region name"
    default  = "westus2"
    type = string
}

variable "network_name" {
    description = "Azure network name"
    default  = "network_project1"
    type = string
}

variable "network_address" {
    description = "Azure network address"
    default  = ["10.0.0.0/16"]
    type = list
}

variable "subnet_name" {
    description = "Azure subnet name"
    default  = "subnet_project1"
    type = string
}

variable "subnet_address" {
    description = "Azure subnet address"
    default  = ["10.0.2.0/24"]
    type = list
}

variable "parent_domain_name" {
    description = "Parent DNS zone name"
    default  = "az.skypod.io"
    type = string
}
