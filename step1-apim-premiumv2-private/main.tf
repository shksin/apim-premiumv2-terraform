# ═══════════════════════════════════════════════════════════════
# Stage 1 — APIM Premium v2 with VNet Injection (Internal mode)
#
# Consumes a pre-existing network (RG, VNet, APIM subnet, PE subnet,
# NSG, private DNS zone `azure-api.net`) — supply the names via vars.
#
# APIM is deployed via the Azure Verified Module
# `Azure/avm-res-apimanagement-service/azurerm` with Internal VNet
# injection + a management Private Endpoint.
#
# Reference: https://learn.microsoft.com/en-us/azure/api-management/inject-vnet-v2
# ═══════════════════════════════════════════════════════════════

# ── Existing networking ──────────────────────────────────────────
data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}

data "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  resource_group_name = data.azurerm_resource_group.rg.name
}

data "azurerm_subnet" "apim" {
  name                 = var.apim_subnet_name
  virtual_network_name = data.azurerm_virtual_network.vnet.name
  resource_group_name  = data.azurerm_resource_group.rg.name
}

data "azurerm_subnet" "pe" {
  name                 = var.pe_subnet_name
  virtual_network_name = data.azurerm_virtual_network.vnet.name
  resource_group_name  = data.azurerm_resource_group.rg.name
}

data "azurerm_private_dns_zone" "apim" {
  name                = var.private_dns_zone_name
  resource_group_name = data.azurerm_resource_group.rg.name
}

# ── APIM Premium v2 (AVM) ────────────────────────────────────────
module "apim" {
  source  = "Azure/avm-res-apimanagement-service/azurerm"
  version = "~> 0.0.8"

  name                = var.apim_name
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name

  publisher_email = var.publisher_email
  publisher_name  = var.publisher_name

  sku_name = "PremiumV2_${var.apim_sku_capacity}"
  zones    = var.apim_sku_capacity >= 3 && length(var.availability_zones) > 0 ? var.availability_zones : null

  virtual_network_type      = "Internal"
  virtual_network_subnet_id = data.azurerm_subnet.apim.id

  # Azure rejects `publicNetworkAccess=Disabled` at CREATE time for APIM
  # with Internal VNet injection. It is accepted on UPDATE, so we set
  # it to false here — apply this stack a second time after the initial
  # create to lock down the management plane.
  public_network_access_enabled = var.public_network_access_enabled

  # Management-plane Private Endpoint. The AVM module hardcodes
  # subresource_names = ["Gateway"] for APIM, and registers DNS records
  # in the supplied azure-api.net zone automatically.
  private_endpoints = {
    mgmt = {
      name                            = "pe-${var.apim_name}-mgmt"
      private_service_connection_name = "psc-${var.apim_name}-mgmt"
      subnet_resource_id              = data.azurerm_subnet.pe.id
      private_dns_zone_resource_ids   = [data.azurerm_private_dns_zone.apim.id]
    }
  }

  enable_telemetry = false
}
