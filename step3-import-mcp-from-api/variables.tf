# ── Identity / target APIM ───────────────────────────────────

variable "subscription_id" {
  description = "Azure subscription ID containing the target APIM instance."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group containing the target APIM instance."
  type        = string
}

variable "apim_name" {
  description = "Name of the existing APIM instance."
  type        = string
}

# ── Source REST API (must already exist in APIM) ─────────────

variable "source_api_name" {
  description = "APIM resource name of the existing REST API to project as an MCP server (e.g. \"todo\")."
  type        = string
}

variable "source_openapi_path" {
  description = "Path to the OpenAPI 3.x JSON spec for the source API. Used to enumerate operations (one MCP tool per operationId)."
  type        = string
  default     = "../open-api-spec/open-api-spec.json"
}

# ── MCP server projection ────────────────────────────────────

variable "mcp_server_api_name" {
  description = "APIM resource name of the MCP-type API."
  type        = string
}

variable "mcp_server_api_path" {
  description = "URL path suffix for the MCP server endpoint."
  type        = string
}

variable "mcp_server_api_display_name" {
  description = "Portal display name for the MCP server API."
  type        = string
}

variable "mcp_server_api_description" {
  description = "Description for the MCP server API."
  type        = string
  default     = ""
}

variable "mcp_server_transport_type" {
  description = "MCP transport type. Supported: 'streamable'."
  type        = string
  default     = "streamable"

  validation {
    condition     = contains(["streamable"], var.mcp_server_transport_type)
    error_message = "mcp_server_transport_type must be 'streamable'."
  }
}

variable "mcp_api_version" {
  description = "ARM API version for the MCP API + tools sub-resources (driven via az rest)."
  type        = string
  default     = "2025-09-01-preview"
}
