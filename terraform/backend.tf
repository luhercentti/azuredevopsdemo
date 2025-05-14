# Keep backend configuration minimal to allow initialization before resources exist
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
  
  # The specific values will be provided by the pipeline during terraform init
  backend "azurerm" {
    # # These will be overridden by your pipeline during init
    # # but having them here helps with local development
    # resource_group_name  = "Test_LuisHernandez"
    # storage_account_name = "sttfstateluishernandez"
    # container_name       = "tfstate"
    # key                  = "terraform.tfstate"
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
  # No credentials here - they come from service connection
}
