terraform {
  required_version = ">= 1.5"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
  }

  # Remote state (Azure Storage) — edit to match your tfstate storage account.
  # Identity running `terraform init` needs Storage Blob Data Contributor.
  backend "azurerm" {
    resource_group_name  = "xxx"           # e.g. "rg-tfstate"
    storage_account_name = "xxx"           # e.g. "sttfstateapimpremv2"
    container_name       = "xxxx"          # e.g. "tfstate"
    key                  = "xxxxx.tfstate" # e.g. "step2-import-api-with-policies.tfstate"
    use_azuread_auth     = true
  }
}

provider "azapi" {
  subscription_id = var.subscription_id
}
