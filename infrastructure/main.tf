# use terraform init to put down this provider
#     terraform plan to show what it will do
#     terraform apply to Make It So.
provider "azurerm" {
  # if you're using a Service Principal (shared account) 
  #
  # specify via:
  #  - terraform.tfvars
  #  - env variable - e.g. TF_VAR_subscription_id
  #  - or in plain text below for others to steal from your git repo :)
  subscription_id = "${var.ARM_SUBSCRIPTION_ID}"
  tenant_id       = "${var.ARM_TENANT_ID}"
  client_id       = "${var.ARM_CLIENT_ID}"
  client_secret   = "${var.ARM_CLIENT_SECRET}"
  #version         = "~> 1.1"
}

# variables that are local to this file.
locals {
  common_tags = {
    createdby   = "terraform"
  }
}

# resource group
resource "azurerm_resource_group" "rg" {
  name     = "${var.resource_group}"
  location = "${var.location}"
  tags {
    createdby = "terraform"
  }

}

# storage account
resource "azurerm_storage_account" "sa" {
  name                      = "${var.storage_account["name"]}"
  resource_group_name       = "${azurerm_resource_group.rg.name}"
  location                  = "${azurerm_resource_group.rg.location}"
  account_tier              = "${var.storage_account["tier"]}"
  account_replication_type  = "${var.storage_account["replicationtype"]}"
  enable_blob_encryption    = true
  enable_file_encryption    = true
  enable_https_traffic_only = true
  tags                      = "${merge(local.common_tags,var.tags)}"  
}

resource "azurerm_storage_share" "software" {
  name = "software"
  resource_group_name  = "${azurerm_resource_group.rg.name}"
  storage_account_name = "${azurerm_storage_account.sa.name}"
  # quote in GB
  quota = 500
}

# automation account
resource "azurerm_automation_account" "automation" {
  name                = "${var.automation_account}"
  location            = "${azurerm_resource_group.rg.location}"
  resource_group_name = "${azurerm_resource_group.rg.name}"

  sku {
    name = "Basic"
  }

  tags                = "${merge(local.common_tags,var.tags)}"    
}

# networking
module "operationalvnet" {
  source              = "github.com/Azure/terraform-azurerm-vnet?ref=v1.0"
  vnet_name           = "${azurerm_resource_group.rg.name}-opsvnet"
  resource_group_name = "${azurerm_resource_group.rg.name}"
  location            = "${var.location}"
  address_space       = "10.0.0.0/16"
  subnet_prefixes     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  subnet_names        = ["websubnet", "bizsubnet", "datasubnet"]
  tags                = "${merge(local.common_tags,var.tags)}"
}

module "mgmtvnet" {
  source              = "github.com/Azure/terraform-azurerm-vnet?ref=v1.0"
  vnet_name           = "${azurerm_resource_group.rg.name}-mgmtvnet"
  resource_group_name = "${azurerm_resource_group.rg.name}"
  location            = "${var.location}"
  address_space       = "10.1.0.0/24"
  subnet_prefixes     = ["10.1.0.0/27"]
  subnet_names        = ["jumpnet1"]
  tags                = "${merge(local.common_tags,var.tags)}"
}

## vnet peer between ops and mgmt vnets
resource "azurerm_virtual_network_peering" "peerToOps" {
  name                         = "mgmtvnet-to-operationalvnet"
  resource_group_name          = "${azurerm_resource_group.rg.name}"
  virtual_network_name         = "${module.mgmtvnet.vnet_name}"
  remote_virtual_network_id    = "${module.operationalvnet.vnet_id}"
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  # doesn't support tagging
}

resource "azurerm_virtual_network_peering" "peerToMgt" {
  name                         = "operationalvnet-to-mgmtvnet"
  resource_group_name          = "${azurerm_resource_group.rg.name}"
  virtual_network_name         = "${module.operationalvnet.vnet_name}"
  remote_virtual_network_id    = "${module.mgmtvnet.vnet_id}"
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  # doesn't support tagging
}


# the mgmt VM

module "win10vm" {
  source              = "github.com/Azure/terraform-azurerm-compute?ref=v1.1.5"
  resource_group_name = "${azurerm_resource_group.rg.name}"
  location            = "${azurerm_resource_group.rg.location}"
  vm_hostname         = "kewwin10"
  vm_os_simple        = "WindowsServer"
  vnet_subnet_id      = "${module.mgmtvnet.vnet_subnets[0]}"  
  admin_password      = "${var.admin_password}"
  public_ip_dns       = ["win10vm-pip"]
  nb_public_ip        = "1"
  remote_port         = "3389"
  vm_os_publisher     = "MicrosoftWindowsDesktop"
  vm_os_offer         = "Windows-10"
  vm_os_sku           = "RS3-Pro"
  vm_size             = "Standard_DS1_v2"
  vnet_subnet_id      = "${module.mgmtvnet.vnet_subnets[0]}"
  tags                = "${merge(
    local.common_tags,
    var.tags,
    map("role", "remote management")
  )}"    
}

# an AD Domain Controller
module "addc" {
  source              = "github.com/Azure/terraform-azurerm-compute?ref=v1.1.5"
  resource_group_name = "${azurerm_resource_group.rg.name}"
  location            = "${azurerm_resource_group.rg.location}"
  vm_hostname         = "addc"
  vm_os_simple        = "WindowsServer"
  admin_password      = "${var.admin_password}"
  nb_public_ip        = "0"
  vm_size             = "Standard_DS1_v2"
  vnet_subnet_id      = "${module.operationalvnet.vnet_subnets[2]}"
  tags                = "${merge(
    local.common_tags,
    var.tags,
    map("role", "AD domain controller")
  )}"    
}

# a SQL VM

module "sqlserver1" {
  source              = "github.com/Azure/terraform-azurerm-compute?ref=v1.1.5"
  resource_group_name = "${azurerm_resource_group.rg.name}"
  location            = "${azurerm_resource_group.rg.location}"
  vm_hostname         = "sqlserver1"
  vm_os_simple        = "WindowsServer"
  admin_password      = "${var.admin_password}"
  nb_public_ip        = "0"
  vm_size             = "Standard_DS2_v2"
  vnet_subnet_id      = "${module.operationalvnet.vnet_subnets[2]}"
  tags                = "${merge(
    local.common_tags,
    var.tags,
    map("role", "sql server engine")
  )}"    
}

# based on https://medium.com/modern-stack/bootstrap-a-vm-to-azure-automation-dsc-using-terraform-f2ba41d25cd2
resource "azurerm_virtual_machine_extension" "dsc" {
  name                 = "DevOpsDSC"
  location             = "${azurerm_resource_group.rg.location}"
  resource_group_name  = "${azurerm_resource_group.rg.name}"
  virtual_machine_name = "sqlserver10"
  publisher            = "Microsoft.Powershell"
  type                 = "DSC"
  type_handler_version = "2.74"
  depends_on           = ["module.sqlserver1"]

  settings = <<SETTINGS
        {
            "WmfVersion": "latest",
            "ModulesUrl": "https://eus2oaasibizamarketprod1.blob.core.windows.net/automationdscpreview/RegistrationMetaConfigV2.zip",
            "ConfigurationFunction": "RegistrationMetaConfigV2.ps1\\RegistrationMetaConfigV2",
            "Privacy": {
                "DataCollection": ""
            },
            "Properties": {
                "RegistrationKey": {
                  "UserName": "PLACEHOLDER_DONOTUSE",
                  "Password": "PrivateSettingsRef:registrationKeyPrivate"
                },
                "RegistrationUrl": "${var.dsc_endpoint}",
                "NodeConfigurationName": "${var.dsc_config}",
                "ConfigurationMode": "${var.dsc_mode}",
                "ConfigurationModeFrequencyMins": 15,
                "RefreshFrequencyMins": 30,
                "RebootNodeIfNeeded": false,
                "ActionAfterReboot": "continueConfiguration",
                "AllowModuleOverwrite": false
            }
        }
    SETTINGS

  protected_settings = <<PROTECTED_SETTINGS
    {
      "Items": {
        "registrationKeyPrivate" : "${var.dsc_key}"
      }
    }
PROTECTED_SETTINGS
}

# based on https://medium.com/modern-stack/bootstrap-a-vm-to-azure-automation-dsc-using-terraform-f2ba41d25cd2
resource "azurerm_virtual_machine_extension" "dsc-ad" {
  name                 = "DevOpsDSC"
  location             = "${azurerm_resource_group.rg.location}"
  resource_group_name  = "${azurerm_resource_group.rg.name}"
  virtual_machine_name = "addc0"
  publisher            = "Microsoft.Powershell"
  type                 = "DSC"
  type_handler_version = "2.74"
  depends_on           = ["module.addc"]

  settings = <<SETTINGS
        {
            "WmfVersion": "latest",
            "ModulesUrl": "https://eus2oaasibizamarketprod1.blob.core.windows.net/automationdscpreview/RegistrationMetaConfigV2.zip",
            "ConfigurationFunction": "RegistrationMetaConfigV2.ps1\\RegistrationMetaConfigV2",
            "Privacy": {
                "DataCollection": ""
            },
            "Properties": {
                "RegistrationKey": {
                  "UserName": "PLACEHOLDER_DONOTUSE",
                  "Password": "PrivateSettingsRef:registrationKeyPrivate"
                },
                "RegistrationUrl": "${var.dsc_endpoint}",
                "NodeConfigurationName": "${var.dsc_config}",
                "ConfigurationMode": "${var.dsc_mode}",
                "ConfigurationModeFrequencyMins": 15,
                "RefreshFrequencyMins": 30,
                "RebootNodeIfNeeded": false,
                "ActionAfterReboot": "continueConfiguration",
                "AllowModuleOverwrite": false
            }
        }
    SETTINGS

  protected_settings = <<PROTECTED_SETTINGS
    {
      "Items": {
        "registrationKeyPrivate" : "${var.dsc_key}"
      }
    }
PROTECTED_SETTINGS
}