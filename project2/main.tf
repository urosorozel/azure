locals {
    workspace_path = "./workspaces/${terraform.workspace}.yaml"
    defaults       = file("${path.module}/config.yaml")
    workspace = fileexists(local.workspace_path) ? file(local.workspace_path) : yamlencode({})
    settings = merge(
        yamldecode(local.defaults),
        yamldecode(local.workspace)
    )
}

data "azurerm_subscription" "current" {
}


# Create subdomain
module "dns" {
  source = "github.com/Azure-Terraform/terraform-azurerm-dns-zone.git"

  child_domain_resource_group_name = azurerm_resource_group.rg_project.name
  child_domain_subscription_id     = data.azurerm_subscription.current.subscription_id 
  child_domain_prefix              = terraform.workspace

  parent_domain_resource_group_name = "dns_skypod"
  parent_domain_subscription_id     = data.azurerm_subscription.current.subscription_id
  parent_domain                     = "${var.parent_domain_name}"

  tags = { "environment" = "${terraform.workspace}"
           "location"    = "uswest2" }
}


# Resource group
resource "azurerm_resource_group" "rg_project" {
    name     = "project2_${terraform.workspace}"
    location = "${var.region_name}"

    tags = {
        environment = "${terraform.workspace}"
    }
}

# Network 
resource "azurerm_virtual_network" "network" {
    name                = "${var.network_name}"
    address_space       = "${var.network_address}"
    location            = azurerm_resource_group.rg_project.location
    resource_group_name = azurerm_resource_group.rg_project.name

    tags = {
        environment = "${terraform.workspace}"
    }
}

# Subnet
resource "azurerm_subnet" "subnet" {
    name                 = "${var.subnet_name}"
    resource_group_name  = azurerm_resource_group.rg_project.name
    virtual_network_name = azurerm_virtual_network.network.name
    address_prefixes       = "${var.subnet_address}"
}

# Public IP for VM
resource "azurerm_public_ip" "vm-project-public" {
    count                       = "${local.settings.vm_count}"
    name                         = "VMPublicIP-${count.index}"
    location                     = azurerm_resource_group.rg_project.location
    resource_group_name          = azurerm_resource_group.rg_project.name 
    allocation_method            = "Dynamic"

    tags = {
        environment = "Terraform Demo"
    }
}

# Create LB
resource "azurerm_lb" "lb-project" {
 name                = "loadBalancer"
 location            = azurerm_resource_group.rg_project.location
 resource_group_name = azurerm_resource_group.rg_project.name

 frontend_ip_configuration {
   name                 = "LBpublicIPAddress"
   public_ip_address_id = azurerm_public_ip.LBpublicIP.id
 }
}

resource "azurerm_lb_backend_address_pool" "lb-address-pool" {
 loadbalancer_id     = azurerm_lb.lb-project.id
 name                = "BackEndAddressPool"
}

# Public LB IP
resource "azurerm_public_ip" "LBpublicIP" {
    name                         = "LBpublicIP"
    location                     = azurerm_resource_group.rg_project.location
    resource_group_name          = azurerm_resource_group.rg_project.name
    allocation_method            = "Static"

    tags = {
        environment = "${terraform.workspace}"
    }
}


# DNS A record for LB
resource "azurerm_dns_a_record" "lb-a-record" {
  name                = "lb"
  zone_name           = module.dns.name
  resource_group_name = azurerm_resource_group.rg_project.name
  ttl                 = 300
  records             = ["${azurerm_public_ip.LBpublicIP.ip_address}"]
}

# HTTP probe
resource "azurerm_lb_probe" "lb-probe" {
  resource_group_name = azurerm_resource_group.rg_project.name
  loadbalancer_id     = azurerm_lb.lb-project.id
  name                = "http-running-probe"
  port                = 3000
}

# LB rule
resource "azurerm_lb_rule" "lb-rule" {
  resource_group_name            = azurerm_resource_group.rg_project.name
  loadbalancer_id                = azurerm_lb.lb-project.id
  name                           = "LBRule80"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 3000
  frontend_ip_configuration_name = "LBpublicIPAddress"
  backend_address_pool_id        = azurerm_lb_backend_address_pool.lb-address-pool.id
  probe_id                       = azurerm_lb_probe.lb-probe.id
}

# Network interface
resource "azurerm_network_interface" "nic" {
    count			= "${local.settings.vm_count}"
    name                        = "nic-${count.index}"
    location                    = azurerm_resource_group.rg_project.location
    resource_group_name         = azurerm_resource_group.rg_project.name

    ip_configuration {
        name                          = "NicConfiguration"
        subnet_id                     = azurerm_subnet.subnet.id
        private_ip_address_allocation = "Dynamic"
        public_ip_address_id          = element(azurerm_public_ip.vm-project-public.*.id, count.index)
    }

    tags = {
        environment = "${terraform.workspace}"
    }
}

# Allow ssh
resource "azurerm_network_security_rule" "example" {
  name                        = "AllowSSH"
  priority                    = 1002
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.rg_project.name 
  network_security_group_name = azurerm_network_security_group.lb-sec-group.name
}

# Create account for diagnostic
resource "random_id" "randomId" {
    keepers = {
        # Generate a new ID only when a new resource group is defined
        resource_group = azurerm_resource_group.rg_project.name
    }

    byte_length = 8
}

# Create storage account for logs
resource "azurerm_storage_account" "sa" {
    name                        = "diag${random_id.randomId.hex}"
    resource_group_name         = azurerm_resource_group.rg_project.name
    location                    = azurerm_resource_group.rg_project.location
    account_replication_type    = "LRS"
    account_tier                = "Standard"

    tags = {
        environment = "${terraform.workspace}"
    }
}

# LB security group
resource "azurerm_network_security_group" "lb-sec-group" {
  name                = "LBSecurityGroup"
  location            = azurerm_resource_group.rg_project.location
  resource_group_name = azurerm_resource_group.rg_project.name

  security_rule {
    name                       = "HTTPallow"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3000"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Port SG
resource "azurerm_network_interface_security_group_association" "sg-port" {
  count = "${local.settings.vm_count}"
  network_interface_id      = element(azurerm_network_interface.nic.*.id, count.index)
  network_security_group_id = azurerm_network_security_group.lb-sec-group.id
}

# Allow SSH
resource "azurerm_network_security_rule" "allow-ssh" {
  name                        = "AllowSSH"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "22"
  resource_group_name         = azurerm_resource_group.rg_project.name
  network_security_group_name = azurerm_network_security_group.lb-sec-group.name
}

# Port to LB group (this is for oubound)
resource "azurerm_network_interface_backend_address_pool_association" "pool-port" {
  count = "${local.settings.vm_count}"
  network_interface_id    = element(azurerm_network_interface.nic.*.id, count.index)
  ip_configuration_name   = "NicConfiguration" 
  backend_address_pool_id = azurerm_lb_backend_address_pool.lb-address-pool.id
}

# Availabili set
resource "azurerm_availability_set" "avset" {
 name                         = "avset"
 location                     = azurerm_resource_group.rg_project.location 
 resource_group_name          = azurerm_resource_group.rg_project.name 
 platform_fault_domain_count  = 2
 platform_update_domain_count = 2
 managed                      = true
}

# Create VM
resource "tls_private_key" "sshkey" {
  algorithm = "RSA"
  rsa_bits = 4096
}

output "tls_private_key" { 
    value = tls_private_key.sshkey.private_key_pem 
    sensitive = true
}

# User data 
data "template_file" "control_user_data" {
  template = "${file("${path.module}/assests/cloud.sh")}"
}

resource "azurerm_linux_virtual_machine" "vm" {
    count                 = "${local.settings.vm_count}"
    name                  = "vm-${count.index}"
    location              = azurerm_resource_group.rg_project.location
    availability_set_id   = azurerm_availability_set.avset.id
    resource_group_name   = azurerm_resource_group.rg_project.name
    network_interface_ids = [element(azurerm_network_interface.nic.*.id, count.index)]
    size                  = "Standard_DS1_v2"
    custom_data           = base64encode(data.template_file.control_user_data.rendered)

    os_disk {
        name              = "myOsDisk-${count.index}"
        caching           = "ReadWrite"
        storage_account_type = "Premium_LRS"
    }

    source_image_reference {
        publisher = "Canonical"
        offer     = "UbuntuServer"
        sku       = "18.04-LTS"
        version   = "latest"
    }

    computer_name  = "vm-${count.index}"
    admin_username = "azureuser"
    disable_password_authentication = true

    admin_ssh_key {
        username       = "azureuser"
        public_key     = tls_private_key.sshkey.public_key_openssh
    }

    boot_diagnostics {
        storage_account_uri = azurerm_storage_account.sa.primary_blob_endpoint
    }

    tags = {
        environment = "${terraform.workspace}"
    }
}


resource "azurerm_dns_a_record" "dns-a" {
  count               = "${local.settings.vm_count}"
  name                = "${element(azurerm_linux_virtual_machine.vm,count.index).name}"
  zone_name           = module.dns.name
  resource_group_name = azurerm_resource_group.rg_project.name
  ttl                 = 300
  records             = "${element(azurerm_linux_virtual_machine.vm,count.index).public_ip_addresses}"
}
