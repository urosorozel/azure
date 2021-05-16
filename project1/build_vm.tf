# Resource group
resource "azurerm_resource_group" "rg_westus2_project1" {
    name     = "tf_rg_project1"
    location = "westus2"

    tags = {
        environment = "Terraform project1"
    }
}

# Network 
resource "azurerm_virtual_network" "network_project1" {
    name                = "network_project1"
    address_space       = ["10.0.0.0/16"]
    location            = "westus2"
    resource_group_name = azurerm_resource_group.rg_westus2_project1.name

    tags = {
        environment = "Terraform project1"
    }
}

# Subnet
resource "azurerm_subnet" "subnet_project1" {
    name                 = "subnet_project1"
    resource_group_name  = azurerm_resource_group.rg_westus2_project1.name
    virtual_network_name = azurerm_virtual_network.network_project1.name
    address_prefixes       = ["10.0.2.0/24"]
}

# Public IP
resource "azurerm_public_ip" "publicIP_project1" {
    name                         = "publicIP_project1"
    location                     = "westus2"
    resource_group_name          = azurerm_resource_group.rg_westus2_project1.name
    allocation_method            = "Dynamic"

    tags = {
        environment = "Terraform project1"
    }
}

# Security group
resource "azurerm_network_security_group" "sg_project1" {
    name                = "sg_project1"
    location            = "westus2"
    resource_group_name = azurerm_resource_group.rg_westus2_project1.name

    security_rule {
        name                       = "SSH"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "22"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }

    tags = {
        environment = "Terraform project1"
    }
}

# Network interface
resource "azurerm_network_interface" "nic_project1" {
    name                        = "nic_project1"
    location                    = "westus2"
    resource_group_name         = azurerm_resource_group.rg_westus2_project1.name

    ip_configuration {
        name                          = "NicConfiguration_project1"
        subnet_id                     = azurerm_subnet.subnet_project1.id
        private_ip_address_allocation = "Dynamic"
        public_ip_address_id          = azurerm_public_ip.publicIP_project1.id
    }

    tags = {
        environment = "Terraform project1"
    }
}

# Connect the security group to the network interface
resource "azurerm_network_interface_security_group_association" "sga_project1" {
    network_interface_id      = azurerm_network_interface.nic_project1.id
    network_security_group_id = azurerm_network_security_group.sg_project1.id
}

# Create account for diagnostic
resource "random_id" "randomId" {
    keepers = {
        # Generate a new ID only when a new resource group is defined
        resource_group = azurerm_resource_group.rg_westus2_project1.name
    }

    byte_length = 8
}

# Create storage account for logs
resource "azurerm_storage_account" "sa_project1" {
    name                        = "diag${random_id.randomId.hex}"
    resource_group_name         = azurerm_resource_group.rg_westus2_project1.name
    location                    = "westus2"
    account_replication_type    = "LRS"
    account_tier                = "Standard"

    tags = {
        environment = "Terraform project1"
    }
}

# Create VM
resource "tls_private_key" "sshkey_project1" {
  algorithm = "RSA"
  rsa_bits = 4096
}

output "tls_private_key_project1" { 
    value = tls_private_key.sshkey_project1.private_key_pem 
    sensitive = true
}

resource "azurerm_linux_virtual_machine" "vm1_prroject1" {
    name                  = "vm11_project1"
    location              = "westus2"
    resource_group_name   = azurerm_resource_group.rg_westus2_project1.name
    network_interface_ids = [azurerm_network_interface.nic_project1.id]
    size                  = "Standard_DS1_v2"

    os_disk {
        name              = "myOsDisk"
        caching           = "ReadWrite"
        storage_account_type = "Premium_LRS"
    }

    source_image_reference {
        publisher = "Canonical"
        offer     = "UbuntuServer"
        sku       = "18.04-LTS"
        version   = "latest"
    }

    computer_name  = "vm1-project1"
    admin_username = "azureuser"
    disable_password_authentication = true

    admin_ssh_key {
        username       = "azureuser"
        public_key     = tls_private_key.sshkey_project1.public_key_openssh
    }

    boot_diagnostics {
        storage_account_uri = azurerm_storage_account.sa_project1.primary_blob_endpoint
    }

    tags = {
        environment = "Terraform project1"
    }
}
