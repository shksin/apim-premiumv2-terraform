terraform {
  required_version = ">= 1.5"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
  }

  # Partial backend config — supply at init time:
  #   terraform init -backend-config=backend.hcl
  backend "azurerm" {}
}

provider "azapi" {
  subscription_id = var.subscription_id
}
