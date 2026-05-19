# ── Identity / target APIM (passed from Stage 1 outputs in CI) ──

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

# ── Backend App Service (created out-of-band by create-mcp-appservice.ps1) ──

variable "mcp_app_service_name" {
  description = "Name of the existing private App Service hosting the MCP REST backend."
  type        = string
}

variable "mcp_app_service_resource_group" {
  description = "Resource group of the App Service."
  type        = string
}

# ── MCP REST API (imported into APIM) ────────────────────────

variable "mcp_rest_api_name" {
  description = "APIM resource name of the imported REST API that backs the MCP server."
  type        = string
  default     = "mcp-rest"
}

variable "mcp_rest_api_path" {
  description = "URL path suffix for the REST API."
  type        = string
  default     = "mcp-rest"
}

variable "mcp_rest_api_display_name" {
  description = "Portal display name for the REST API."
  type        = string
  default     = "MCP REST Backend"
}

variable "mcp_rest_api_description" {
  description = "Description for the REST API."
  type        = string
  default     = "Private App Service REST API exposed through APIM. Source of truth for the MCP server."
}

# ── MCP server projection (apiType=mcp) ──────────────────────

variable "mcp_server_api_name" {
  description = "APIM resource name of the MCP-type API."
  type        = string
  default     = "mcp-rest-mcp"
}

variable "mcp_server_api_path" {
  description = "URL path suffix for the MCP server endpoint."
  type        = string
  default     = "mcp-server"
}

variable "mcp_server_api_display_name" {
  description = "Portal display name for the MCP server API."
  type        = string
  default     = "MCP REST Backend (MCP server)"
}

variable "mcp_server_api_description" {
  description = "Description for the MCP server API."
  type        = string
  default     = "MCP server projection of the MCP REST Backend API. Exposes selected operations as MCP tools."
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

variable "mcp_tools_api_version" {
  description = "ARM API version for MCP server + tools sub-resources (driven via az rest)."
  type        = string
  default     = "2025-09-01-preview"
}

variable "mcp_tools" {
  description = <<-EOT
    MCP tools to expose. Map keyed by tool name → operationId on the source REST API.
  EOT
  type = map(object({
    display_name = optional(string)
    description  = string
    operation_id = string
  }))
  default = {
    hello = {
      description  = "Returns a greeting from the private backend."
      operation_id = "hello"
    }
    echo = {
      description  = "Echoes back the supplied text. Pass the text to echo in the 'text' query parameter."
      operation_id = "echo"
    }
  }
}

# ── Asset paths ──────────────────────────────────────────────

variable "openapi_spec_path" {
  description = "Path to the MCP REST OpenAPI 3.x JSON spec (relative to this module)."
  type        = string
  default     = "mcp-rest-openapi.json"
}

variable "policy_xml_path" {
  description = "Path to the APIM policy XML file (relative to this module)."
  type        = string
  default     = "policy.xml"
}
