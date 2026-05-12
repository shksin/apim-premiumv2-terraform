# ═══════════════════════════════════════════════════════════════
# Step 2 — Import Petstore API from public OpenAPI spec + apply policy
#
# Creates:
#   - Petstore API (imported from petstore3.swagger.io OpenAPI 3.0 spec)
#   - API-level policy from policy.xml
#
# Depends on: azapi_resource.apim (Step 1)
#
# NOTE: APIM fetches the OpenAPI spec from the public internet at import
# time. The NSG DenyInternetOutbound rule in Step 1 will block this.
# Options:
#   a) Temporarily allow outbound to Internet during import
#   b) Host the spec in Azure Blob Storage and update the value URL
# ═══════════════════════════════════════════════════════════════

locals {
  api_policy = file("${path.module}/policy.xml")
}

# ── Petstore API ─────────────────────────────────────────────
resource "azapi_resource" "petstore_api" {
  type      = "Microsoft.ApiManagement/service/apis@2024-05-01"
  name      = "petstore"
  parent_id = azapi_resource.apim.id

  body = {
    properties = {
      displayName          = "Petstore API"
      description          = "Sample Petstore API imported from public OpenAPI 3.0 spec"
      path                 = "petstore"
      protocols            = ["https"]
      subscriptionRequired = true

      # openapi+json-link tells APIM to fetch the spec from the URL
      # Use openapi+json and inline the JSON content if outbound is blocked
      format = "openapi+json-link"
      value  = "https://petstore3.swagger.io/api/v3/openapi.json"
    }
  }

  depends_on = [azapi_resource.apim]
}

# ── API Policy ───────────────────────────────────────────────
# Applies policy.xml to the Petstore API.
# The child resource name must always be "policy" — APIM singleton.
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
