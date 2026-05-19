# ═══════════════════════════════════════════════════════════════
# Stage 2 — Import an existing REST API into APIM + apply policy
#
# Imports a REST API (from a consumer-supplied OpenAPI spec) into
# APIM and applies an API-level policy. The API's `serviceUrl`
# points at the consumer's existing backend (e.g. App Service).
#
# Resources created:
#   - API (imported from local OpenAPI spec, serviceUrl = backend URL)
#   - API-level policy
# ═══════════════════════════════════════════════════════════════

locals {
  apim_id        = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.ApiManagement/service/${var.apim_name}"
  api_policy_xml = file("${path.module}/${var.policy_xml_path}")
  openapi_spec   = file("${path.module}/${var.openapi_spec_path}")
}

resource "azapi_resource" "api" {
  type      = "Microsoft.ApiManagement/service/apis@2024-05-01"
  name      = var.api_name
  parent_id = local.apim_id

  body = {
    properties = {
      displayName          = var.api_display_name
      description          = var.api_description
      path                 = var.api_path
      serviceUrl           = var.api_backend_url
      protocols            = var.api_protocols
      subscriptionRequired = var.api_subscription_required
      format               = "openapi+json"
      value                = local.openapi_spec
    }
  }
}

resource "azapi_resource" "api_policy" {
  type      = "Microsoft.ApiManagement/service/apis/policies@2024-05-01"
  name      = "policy"
  parent_id = azapi_resource.api.id

  body = {
    properties = {
      format = "rawxml"
      value  = local.api_policy_xml
    }
  }

  depends_on = [azapi_resource.api]
}
