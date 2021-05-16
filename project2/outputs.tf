output "domain" {
  value = module.dns.name
}

output "instances" {
  value = azurerm_linux_virtual_machine.vm 
  sensitive = true
}
