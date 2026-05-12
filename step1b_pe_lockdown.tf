# ═══════════════════════════════════════════════════════════════
# Step 1b — Lock down the APIM management plane
#
# What it does:
#   1. Creates a dedicated subnet for Private Endpoints (no delegation)
#   2. Creates a Private Endpoint for APIM (groupId = "Gateway")
#      → this exposes the management/configuration/SCM/portal endpoints
#        privately under <apim>.<sub>.azure-api.net
#   3. Adds private DNS A records for the management/portal/scm/dev hostnames
#   4. Flips properties.publicNetworkAccess = "Disabled" on the APIM resource
#      (must be a post-create update — APIM rejects this at creation time)
#
# Result: ARM data-plane proxy / direct management API / dev portal / SCM
# are no longer reachable from the public internet. The gateway was already
# private (Internal VNet injection in step 1).
# ═══════════════════════════════════════════════════════════════

# ── Private Endpoint subnet ──────────────────────────────────
# Private Endpoints require:
#   - No subnet delegation
#   - privateEndpointNetworkPolicies disabled (default since 2024)
resource "azurerm_subnet" "pe" {
  name                 = var.pe_subnet_name
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.pe_subnet_prefix]

  private_endpoint_network_policies = "Disabled"
}

# ── Private Endpoint targeting APIM (groupId = Gateway) ──────
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

  # Auto-register all APIM hostnames (gateway, management, scm, portal,
  # developer, configuration) into the existing azure-api.net private zone.
  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.apim.id]
  }

  depends_on = [azapi_resource.apim]
}

# ── Disable public network access on the APIM management plane ──
# Must be a separate PATCH after create + after the Private Endpoint is in
# place (APIM refuses publicNetworkAccess=Disabled at create time and also
# refuses it without a Private Endpoint connected).
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
