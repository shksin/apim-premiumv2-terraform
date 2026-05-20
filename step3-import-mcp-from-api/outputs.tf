output "mcp_server_api_id" {
  description = "ARM resource ID of the MCP-type API."
  value       = "${local.apim_id}/apis/${var.mcp_server_api_name}"
}

output "mcp_server_url" {
  description = "Base URL for the MCP server endpoint."
  value       = "https://${var.apim_name}.azure-api.net/${var.mcp_server_api_path}"
}

output "mcp_server_endpoint" {
  description = "Streamable-HTTP MCP endpoint to configure in MCP clients."
  value       = "https://${var.apim_name}.azure-api.net/${var.mcp_server_api_path}/mcp"
}

output "mcp_tool_count" {
  description = "Number of MCP tools created (one per operation in the source API)."
  value       = length(local.source_operation_ids)
}

output "mcp_tool_names" {
  description = "Names of MCP tools created (operationIds from the source OpenAPI spec)."
  value       = local.source_operation_ids
}
