# ═══════════════════════════════════════════════════════════════
# Stage 2 — Import Petstore API + apply policy
#
#
# Resources created:
#   - Petstore API (imported from local OpenAPI spec)
#   - API-level policy (rate-limit + correlation id)
# ═══════════════════════════════════════════════════════════════

locals {
  apim_id          = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.ApiManagement/service/${var.apim_name}"
  api_policy       = file("${path.module}/${var.policy_xml_path}")
  petstore_openapi = file("${path.module}/${var.openapi_spec_path}")
}

resource "azapi_resource" "petstore_api" {
  type      = "Microsoft.ApiManagement/service/apis@2024-05-01"
  name      = var.petstore_api_name
  parent_id = local.apim_id

  body = {
    properties = {
      displayName          = var.petstore_api_display_name
      description          = var.petstore_api_description
      path                 = var.petstore_api_path
      protocols            = ["https"]
      subscriptionRequired = true
      format               = "openapi+json"
      value                = local.petstore_openapi
    }
  }
}

resource "azapi_resource" "petstore_api_policy" {
  type      = "Microsoft.ApiManagement/service/apis/policies@2024-05-01"
  name      = "policy"
  parent_id = azapi_resource.petstore_api.id

  body = {
    properties = {
      format = "rawxml"
      value  = local.api_policy
    }
  }

  depends_on = [azapi_resource.petstore_api]
}
