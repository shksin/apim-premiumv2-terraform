# ── APIM outputs ─────────────────────────────────────────────

output "apim_resource_id" {
  description = "Resource ID of the APIM instance."
  value       = azapi_resource.apim.id
}

output "apim_gateway_url" {
  description = "Private gateway URL for the APIM instance. Only resolvable within the VNet or peered networks."
  value       = "https://${var.apim_name}.azure-api.net"
}

output "apim_private_ip" {
  description = "Private IP address of the APIM gateway."
  value       = azapi_resource.apim.output.properties.privateIPAddresses[0]
}

output "apim_management_url" {
  description = "Management API URL for the APIM instance."
  value       = "https://${var.apim_name}.management.azure-api.net"
}

# ── API outputs ───────────────────────────────────────────────

output "petstore_api_url" {
  description = "Base URL for the Petstore API through APIM."
  value       = "https://${var.apim_name}.azure-api.net/petstore"
}

output "mcp_server_endpoint" {
  description = "MCP server endpoint URL. Use this in MCP client configuration."
  value       = "https://${var.apim_name}.azure-api.net/mcp-server/mcp"
}

# ── Networking outputs ────────────────────────────────────────

output "vnet_id" {
  description = "Resource ID of the VNet."
  value       = azurerm_virtual_network.vnet.id
}

output "apim_subnet_id" {
  description = "Resource ID of the APIM subnet."
  value       = azurerm_subnet.apim.id
}

output "private_dns_zone_id" {
  description = "Resource ID of the private DNS zone."
  value       = azurerm_private_dns_zone.apim.id
}
