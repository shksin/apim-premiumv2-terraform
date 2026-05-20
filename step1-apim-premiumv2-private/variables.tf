# ── Subscription / identity ──────────────────────────────────

variable "subscription_id" {
  description = "Azure subscription ID where resources will be deployed."
  type        = string
}

# ── Existing resource group / location ───────────────────────

variable "location" {
  description = "Azure region. Must match the region of the pre-existing VNet."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the existing resource group that contains the VNet."
  type        = string
}

# ── APIM ─────────────────────────────────────────────────────

variable "apim_name" {
  description = "Name of the APIM instance. Must be globally unique."
  type        = string
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

variable "availability_zones" {
  description = "Availability zones for the APIM instance. Set to [] if the subscription / region lacks AZ capability."
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "public_network_access_enabled" {
  description = "Whether the APIM management plane is reachable from the public internet. Leave UNSET on the first apply so the AVM module's default applies (Azure rejects Disabled at create time for Internal VNet injection). On a subsequent apply pass `-var=public_network_access_enabled=false` to lock down the management plane to the Private Endpoint."
  type        = bool
  default     = null
}

# ── Existing networking  ──

variable "vnet_name" {
  description = "Name of the existing VNet."
  type        = string
}

variable "apim_subnet_name" {
  description = "Name of the existing APIM subnet (delegated to Microsoft.Web/hostingEnvironments)."
  type        = string
}

variable "pe_subnet_name" {
  description = "Name of the existing subnet hosting the APIM management Private Endpoint."
  type        = string
}

variable "private_dns_zone_name" {
  description = "Name of the existing private DNS zone for APIM (azure-api.net)."
  type        = string
}
