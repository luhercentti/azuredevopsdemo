# Use existing resource group as data source
data "azurerm_resource_group" "main" {
  name = "Test_LuisHernandez"
}

# Import current client configuration
data "azurerm_client_config" "current" {}

resource "random_id" "deployment_suffix" {
  byte_length = 4
}

# Deploy Key Vault using ARM template
resource "azurerm_resource_group_template_deployment" "key_vault" {
  name                = "kv-deploy-${random_id.deployment_suffix.hex}"
  resource_group_name = data.azurerm_resource_group.main.name
  deployment_mode     = "Incremental"
  template_content    = file("${path.module}/arm-templates/keyvault.json")
  parameters_content  = jsonencode({
    "keyVaultName" = {
      "value" = "kv-luishernandez-prueba"
    },
    "location" = {
      "value" = data.azurerm_resource_group.main.location
    },
    "tenantId" = {
      "value" = data.azurerm_client_config.current.tenant_id
    },
    "objectId" = {
      "value" = data.azurerm_client_config.current.object_id
    }
  })
}

# Get reference to the Key Vault
data "azurerm_key_vault" "main" {
  name                = "kv-luishernandez-prueba"
  resource_group_name = data.azurerm_resource_group.main.name
  depends_on          = [azurerm_resource_group_template_deployment.key_vault]
}

resource "azurerm_public_ip" "main" {
  name                = "vm-public-ip"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
  allocation_method   = "Dynamic"
}

resource "azurerm_network_security_group" "main" {
  name                = "vm-nsg"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name

  security_rule {
    name                       = "RDP"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTP"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTPS"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "SQL"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "1433"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "WinRM-HTTP"
    priority                   = 1004
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5985"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_virtual_network" "main" {
  name                = "vm-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
}

resource "azurerm_subnet" "main" {
  name                 = "internal"
  resource_group_name  = data.azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]

  depends_on = [azurerm_virtual_network.main]
}

resource "azurerm_network_interface" "main" {
  name                = "vm-nic"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main.id
  }
}

# # Create local variables for VM credentials
# resource "random_password" "vm_password" {
#   length           = 16
#   special          = true
#   override_special = "!@#$%^&*()-_=+[]{}<>:?"
# }

locals {
  vm_username = "azureadmin"
  #vm_password = random_password.vm_password.result
  vm_password  = "secretinitialpassword!"
}

# Store VM credentials in Key Vault using ARM template deployment
resource "azurerm_resource_group_template_deployment" "key_vault_secrets" {
  name                = "keyvault-secrets-deployment"
  resource_group_name = data.azurerm_resource_group.main.name
  deployment_mode     = "Incremental"
  
  template_content = <<TEMPLATE
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "keyVaultName": {
      "type": "string",
      "metadata": {
        "description": "Name of the Key Vault"
      }
    },
    "vmUsername": {
      "type": "string",
      "metadata": {
        "description": "VM admin username"
      }
    },
    "vmPassword": {
      "type": "securestring",
      "metadata": {
        "description": "VM admin password"
      }
    }
  },
  "resources": [
    {
      "type": "Microsoft.KeyVault/vaults/secrets",
      "apiVersion": "2021-11-01-preview",
      "name": "[concat(parameters('keyVaultName'), '/vm-admin-username')]",
      "properties": {
        "value": "[parameters('vmUsername')]"
      }
    },
    {
      "type": "Microsoft.KeyVault/vaults/secrets",
      "apiVersion": "2021-11-01-preview",
      "name": "[concat(parameters('keyVaultName'), '/vm-admin-password')]",
      "properties": {
        "value": "[parameters('vmPassword')]"
      }
    }
  ]
}
TEMPLATE

  parameters_content = jsonencode({
    "keyVaultName" = {
      "value" = data.azurerm_key_vault.main.name
    },
    "vmUsername" = {
      "value" = local.vm_username
    },
    "vmPassword" = {
      "value" = local.vm_password
    }
  })

  depends_on = [azurerm_resource_group_template_deployment.key_vault]
}

resource "azurerm_windows_virtual_machine" "main" {
  name                = "vm-testluishernandez"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
  computer_name       = "vm-luishernz"
  size                = "Standard_D2s_v3"
  admin_username      = local.vm_username
  admin_password      = local.vm_password
  network_interface_ids = [
    azurerm_network_interface.main.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }

  # Enable WinRM for remote PowerShell execution
  winrm_listener {
    protocol = "Http"
  }

  # Enable VM Agent
  provision_vm_agent = true
  
  custom_data = filebase64("${path.module}/bootstrap.ps1")

  depends_on = [azurerm_resource_group_template_deployment.key_vault_secrets]
}

resource "azurerm_virtual_machine_extension" "bootstrap" {
  name                 = "bootstrap-install"
  virtual_machine_id   = azurerm_windows_virtual_machine.main.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  protected_settings = <<PROTECTED_SETTINGS
    {
      "commandToExecute": "powershell -ExecutionPolicy Unrestricted -EncodedCommand ${textencodebase64(file("${path.module}/bootstrap.ps1"), "UTF-16LE")}"
    }
  PROTECTED_SETTINGS

}


resource "azurerm_managed_disk" "data" {
  name                 = "vm-data-disk"
  location             = data.azurerm_resource_group.main.location
  resource_group_name  = data.azurerm_resource_group.main.name
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = 128

  lifecycle {
    ignore_changes = [
      disk_size_gb,
      storage_account_type
    ]
    create_before_destroy = false
  }  
}

resource "azurerm_virtual_machine_data_disk_attachment" "main" {
  managed_disk_id    = azurerm_managed_disk.data.id
  virtual_machine_id = azurerm_windows_virtual_machine.main.id
  lun                = "10"
  caching            = "ReadWrite"

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_network_interface_security_group_association" "main" {
  network_interface_id      = azurerm_network_interface.main.id
  network_security_group_id = azurerm_network_security_group.main.id
}

# Outputs
output "vm_public_ip" {
  value = azurerm_public_ip.main.ip_address
}

output "key_vault_name" {
  value = data.azurerm_key_vault.main.name
}

output "vm_admin_username_secret_name" {
  value = "vm-admin-username"
}

output "vm_admin_password_secret_name" {
  value = "vm-admin-password"
}

# resource "azurerm_management_lock" "vm_lock" {
#   name       = "vm-delete-lock"
#   scope      = azurerm_windows_virtual_machine.main.id
#   lock_level = "CanNotDelete"
#   notes      = "This VM is protected from deletion."
# }
