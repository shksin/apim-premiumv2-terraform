terraform {
  required_version = ">= 1.5"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # ── Remote state (Azure Storage) ──────────────────────────
  # Edit the values below to match your tfstate storage account.
  # The identity running `terraform init` needs Storage Blob Data
  # Contributor on the storage account (Azure AD auth).
  backend "azurerm" {
    resource_group_name  = "<your-tfstate-rg>"           # e.g. "rg-tfstate"
    storage_account_name = "<your-tfstate-storage-acct>" # globally unique, 3–24 lowercase alphanumeric
    container_name       = "<your-tfstate-container>"    # e.g. "tfstate"
    key                  = "<your-tfstate-key>"          # e.g. "apim-premiumv2.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

provider "azapi" {
  subscription_id = var.subscription_id
}
