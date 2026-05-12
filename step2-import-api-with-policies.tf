# ═══════════════════════════════════════════════════════════════
# Step 2 — Import Petstore API from a LOCAL OpenAPI spec + apply policy
#
# Creates:
#   - Petstore API (imported from ./petstore-openapi.json — bundled in the repo)
#   - API-level policy from policy.xml
#
# Depends on: azapi_resource.apim (Step 1)
#
# The spec is read from disk and inlined into the ARM request body, so the
# APIM RP never has to reach out to the public internet. This keeps the
# deployment fully self-contained and reproducible (no dependency on
# petstore3.swagger.io being up or returning the same content).
# ═══════════════════════════════════════════════════════════════

locals {
  api_policy       = file("${path.module}/policy.xml")
  petstore_openapi = file("${path.module}/petstore-openapi.json")
}

# ── Petstore API ─────────────────────────────────────────────
resource "azapi_resource" "petstore_api" {
  type      = "Microsoft.ApiManagement/service/apis@2024-05-01"
  name      = "petstore"
  parent_id = azapi_resource.apim.id

  body = {
    properties = {
      displayName          = "Petstore API"
      description          = "Sample Petstore API imported from a local OpenAPI 3.0 spec"
      path                 = "petstore"
      protocols            = ["https"]
      subscriptionRequired = true

      # openapi+json (no "-link" suffix) → APIM treats `value` as the inline
      # spec content, not a URL to fetch. No outbound call required.
      format = "openapi+json"
      value  = local.petstore_openapi
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
