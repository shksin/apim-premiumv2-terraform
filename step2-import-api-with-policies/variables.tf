# ── Identity / target APIM (from step 1's outputs) ───────────

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

# ── API definition  ─────────

variable "api_name" {
  description = "APIM resource name (id segment) of the API to import. Example: \"todo\"."
  type        = string
}

variable "api_path" {
  description = "URL path suffix for the API (https://{apim}.azure-api.net/{api_path}). Example: \"todo\"."
  type        = string
}

variable "api_display_name" {
  description = "Display name shown in the APIM portal."
  type        = string
}

variable "api_description" {
  description = "Description for the API."
  type        = string
  default     = ""
}

variable "api_backend_url" {
  description = "Upstream service URL set as the API's serviceUrl (e.g. the App Service hosting the backend)."
  type        = string
}

variable "api_protocols" {
  description = "Protocols the API is exposed on."
  type        = list(string)
  default     = ["https"]
}

variable "api_subscription_required" {
  description = "Whether callers must include an APIM subscription key."
  type        = bool
  default     = true
}

# ── Spec / policy file paths (consumer-supplied) ─────────────

variable "openapi_spec_path" {
  description = "Path to the OpenAPI 3.x JSON spec file (relative to this module). Typically points at ../sample/open-api-spec.json so step 2 and step 3 share the same file."
  type        = string
  default     = "../sample/open-api-spec.json"
}

variable "policy_xml_path" {
  description = "Path to the APIM policy XML file (relative to this module). A sample policy.xml ships at ../sample/policy.xml — replace with your own."
  type        = string
  default     = "../sample/policy.xml"
}
