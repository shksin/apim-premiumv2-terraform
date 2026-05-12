variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "australiaeast"
}

variable "resource_group_name" {
  description = "Name of the resource group."
  type        = string
  default     = "rg-apim-premiumv2"
}

variable "apim_name" {
  description = "Name of the APIM instance. Must be globally unique."
  type        = string
  default     = "apim-premiumv2-demo"
}

variable "publisher_email" {
  description = "Publisher email address for the APIM instance."
  type        = string
}

variable "publisher_name" {
  description = "Publisher display name for the APIM instance."
  type        = string
}

variable "apim_sku_capacity" {
  description = "Number of APIM Premium v2 scale units. Fixed at 3 (required for Availability Zone support)."
  type        = number
  default     = 3

  validation {
    condition     = var.apim_sku_capacity == 3
    error_message = "APIM Premium v2 capacity must be 3."
  }
}

variable "vnet_name" {
  description = "Name of the Virtual Network."
  type        = string
  default     = "vnet-apim"
}

variable "vnet_address_space" {
  description = "Address space for the VNet."
  type        = string
  default     = "10.0.0.0/16"
}

variable "apim_subnet_name" {
  description = "Name of the APIM subnet."
  type        = string
  default     = "snet-apim"
}

variable "apim_subnet_prefix" {
  description = "CIDR for the APIM subnet. Minimum /27, recommended /24."
  type        = string
  default     = "10.0.1.0/24"
}

variable "availability_zones" {
  description = "Availability zones for the APIM instance."
  type        = list(string)
  default     = ["1", "2", "3"]
}

# ── Management plane lockdown ────────────────────────────────

variable "pe_subnet_name" {
  description = "Name of the subnet hosting the APIM management Private Endpoint."
  type        = string
  default     = "snet-apim-pe"
}

variable "pe_subnet_prefix" {
  description = "CIDR for the Private Endpoint subnet. Must NOT have delegation."
  type        = string
  default     = "10.0.2.0/27"
}

# ── Step 3 ───────────────────────────────────────────────────

variable "mcp_app_service_name" {
  description = "Name of the existing App Service hosting the MCP server."
  type        = string
}

variable "mcp_app_service_resource_group" {
  description = "Resource group of the existing App Service."
  type        = string
}
