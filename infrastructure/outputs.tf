output "resource group site1" {
    value = "${azurerm_resource_group.rg.name}"
}

output "storage account" {
    value = "${azurerm_storage_account.sa.name}"
}
/* 
output "win10vm_public_ip" {
  value = "${module.win10vm.public_ip_address}"
}
*/