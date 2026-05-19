output "mcp_rest_api_id" {
  description = "ARM resource ID of the imported REST API."
  value       = azapi_resource.mcp_rest_api.id
}

output "mcp_rest_api_url" {
  description = "Base URL for the REST API behind the MCP server."
  value       = "https://${var.apim_name}.azure-api.net/${var.mcp_rest_api_path}"
}

output "mcp_server_url" {
  description = "Base URL for the MCP server endpoint."
  value       = "https://${var.apim_name}.azure-api.net/${var.mcp_server_api_path}"
}

output "mcp_server_endpoint" {
  description = "Streamable-HTTP MCP endpoint to configure in MCP clients."
  value       = "https://${var.apim_name}.azure-api.net/${var.mcp_server_api_path}/mcp"
}

output "mcp_backend_hostname" {
  description = "Default hostname of the private App Service (resolved over private link)."
  value       = data.azurerm_linux_web_app.mcp_backend.default_hostname
}
