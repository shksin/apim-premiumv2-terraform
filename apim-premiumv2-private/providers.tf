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
  # Partial config — supply the rest at `terraform init` time:
  #   terraform init `
  #     -backend-config="resource_group_name=<tfstate-rg>" `
  #     -backend-config="storage_account_name=<tfstate-sa>" `
  #     -backend-config="container_name=tfstate" `
  #     -backend-config="key=stage1-platform.tfstate"
  # Or point at a backend.hcl file:
  #   terraform init -backend-config=backend.hcl
  backend "azurerm" {}
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

provider "azapi" {
  subscription_id = var.subscription_id
}
