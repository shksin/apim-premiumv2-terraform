terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }

  # Remote state (Azure Storage) — edit to match your tfstate storage account.
  # Identity running `terraform init` needs Storage Blob Data Contributor.
  backend "azurerm" {
    resource_group_name  = "xxx"           # e.g. "rg-tfstate"
    storage_account_name = "xxx"           # e.g. "sttfstateapimpremv2"
    container_name       = "xxxx"          # e.g. "tfstate"
    key                  = "xxxxx.tfstate" # e.g. "step3-import-mcp-from-api.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
