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
  description = "Name of the existing APIM instance to import the API into."
  type        = string
}

# ── API definition ───────────────────────────────────────────

variable "petstore_api_name" {
  description = "APIM resource name of the imported Petstore API."
  type        = string
  default     = "petstore"
}

variable "petstore_api_path" {
  description = "URL path suffix for the Petstore API (https://{apim}.azure-api.net/{path})."
  type        = string
  default     = "petstore"
}

variable "petstore_api_display_name" {
  description = "Display name shown in the APIM portal."
  type        = string
  default     = "Petstore API"
}

variable "petstore_api_description" {
  description = "Description for the Petstore API."
  type        = string
  default     = "Sample Petstore API imported from a local OpenAPI 3.0 spec"
}

# ── Spec / policy file paths (defaults bundled alongside this stage) ──

variable "openapi_spec_path" {
  description = "Path to the OpenAPI 3.x JSON spec file (relative to this module)."
  type        = string
  default     = "petstore-openapi.json"
}

variable "policy_xml_path" {
  description = "Path to the APIM policy XML file (relative to this module)."
  type        = string
  default     = "policy.xml"
}
