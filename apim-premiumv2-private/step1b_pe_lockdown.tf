# ═══════════════════════════════════════════════════════════════
# Stage 1b — Lock down the APIM management plane
#   - PE subnet (no delegation)
#   - Private Endpoint for APIM (groupId = "Gateway")
#   - publicNetworkAccess = "Disabled" on APIM (post-create PATCH)
# ═══════════════════════════════════════════════════════════════

resource "azurerm_subnet" "pe" {
  name                 = var.pe_subnet_name
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.pe_subnet_prefix]

  private_endpoint_network_policies = "Disabled"
}

resource "azurerm_private_endpoint" "apim_mgmt" {
  name                = "pe-${var.apim_name}-mgmt"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.pe.id

  private_service_connection {
    name                           = "psc-${var.apim_name}-mgmt"
    private_connection_resource_id = azapi_resource.apim.id
    is_manual_connection           = false
    subresource_names              = ["Gateway"]
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.apim.id]
  }

  depends_on = [azapi_resource.apim]
}

resource "azapi_update_resource" "apim_disable_public" {
  type        = "Microsoft.ApiManagement/service@2024-05-01"
  resource_id = azapi_resource.apim.id

  body = {
    properties = {
      publicNetworkAccess = "Disabled"
    }
  }

  depends_on = [azurerm_private_endpoint.apim_mgmt]

  timeouts {
    update = "60m"
  }
}
