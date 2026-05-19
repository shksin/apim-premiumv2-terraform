# ═══════════════════════════════════════════════════════════════
# Stage 3 — Import REST API + expose as MCP server
#

#
# Resources:
#   1. REST API in APIM (mcp_rest_api_name) — backend points at the
#      private App Service via privatelink.azurewebsites.net
#   2. API-level policy on the REST API
#   3. MCP-type API (mcp_server_api_name) projecting the REST API,
#      created via `az rest` (azapi schema doesn't yet cover type=mcp)
#   4. MCP tools — one per entry in var.mcp_tools, also via `az rest`
# ═══════════════════════════════════════════════════════════════

locals {
  apim_id          = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.ApiManagement/service/${var.apim_name}"
  api_policy       = file("${path.module}/${var.policy_xml_path}")
  mcp_rest_openapi = file("${path.module}/${var.openapi_spec_path}")
}

# ── Look up the private App Service for its default hostname ──
data "azurerm_linux_web_app" "mcp_backend" {
  name                = var.mcp_app_service_name
  resource_group_name = var.mcp_app_service_resource_group
}

# ── REST API in APIM ─────────────────────────────────────────
resource "azapi_resource" "mcp_rest_api" {
  type      = "Microsoft.ApiManagement/service/apis@2025-03-01-preview"
  name      = var.mcp_rest_api_name
  parent_id = local.apim_id

  body = {
    properties = {
      displayName          = var.mcp_rest_api_display_name
      description          = var.mcp_rest_api_description
      path                 = var.mcp_rest_api_path
      protocols            = ["https"]
      subscriptionRequired = true
      serviceUrl           = "https://${data.azurerm_linux_web_app.mcp_backend.default_hostname}"
      format               = "openapi+json"
      value                = local.mcp_rest_openapi
    }
  }
}

# ── REST API policy ──────────────────────────────────────────
resource "azapi_resource" "mcp_rest_api_policy" {
  type      = "Microsoft.ApiManagement/service/apis/policies@2024-05-01"
  name      = "policy"
  parent_id = azapi_resource.mcp_rest_api.id

  body = {
    properties = {
      format = "rawxml"
      value  = local.api_policy
    }
  }

  depends_on = [azapi_resource.mcp_rest_api]
}

# ── MCP server API + tools (driven via az rest @ 2025-09-01-preview) ──
locals {
  mcp_tools_api = var.mcp_tools_api_version
  mcp_arm_base  = "https://management.azure.com${local.apim_id}/apis/${var.mcp_server_api_name}"

  mcp_server_body = jsonencode({
    properties = {
      displayName          = var.mcp_server_api_display_name
      description          = var.mcp_server_api_description
      path                 = var.mcp_server_api_path
      protocols            = ["https"]
      subscriptionRequired = true
      type                 = "mcp"
      apiType              = "mcp"
      sourceApiId          = azapi_resource.mcp_rest_api.id
      mcpProperties = {
        transportType = var.mcp_server_transport_type
      }
    }
  })

  mcp_tool_bodies = {
    for name, tool in var.mcp_tools :
    name => jsonencode({
      properties = {
        displayName = coalesce(tool.display_name, name)
        description = tool.description
        operationId = "/apis/${azapi_resource.mcp_rest_api.name}/operations/${tool.operation_id}"
      }
    })
  }
}

resource "null_resource" "mcp_server_api" {
  triggers = {
    body    = local.mcp_server_body
    api_ver = local.mcp_tools_api
  }

  provisioner "local-exec" {
    interpreter = ["pwsh", "-NoProfile", "-Command"]
    command     = <<-EOT
      $body = @'
      ${local.mcp_server_body}
      '@
      $tmp = New-TemporaryFile
      Set-Content -Path $tmp -Value $body -Encoding utf8
      az rest --method put `
        --url "${local.mcp_arm_base}?api-version=${local.mcp_tools_api}" `
        --body "@$tmp" `
        --headers "Content-Type=application/json" `
        --only-show-errors -o none
      $code = $LASTEXITCODE
      Remove-Item $tmp -Force
      if ($code -ne 0) { throw "az rest PUT ${var.mcp_server_api_name} failed (exit $code)" }
    EOT
  }

  depends_on = [azapi_resource.mcp_rest_api]
}

resource "null_resource" "mcp_tool" {
  for_each = var.mcp_tools

  triggers = {
    body    = local.mcp_tool_bodies[each.key]
    api_ver = local.mcp_tools_api
  }

  provisioner "local-exec" {
    interpreter = ["pwsh", "-NoProfile", "-Command"]
    command     = <<-EOT
      $body = @'
      ${local.mcp_tool_bodies[each.key]}
      '@
      $tmp = New-TemporaryFile
      Set-Content -Path $tmp -Value $body -Encoding utf8
      az rest --method put `
        --url "${local.mcp_arm_base}/tools/${each.key}?api-version=${local.mcp_tools_api}" `
        --body "@$tmp" `
        --headers "Content-Type=application/json" `
        --only-show-errors -o none
      $code = $LASTEXITCODE
      Remove-Item $tmp -Force
      if ($code -ne 0) { throw "az rest PUT tool ${each.key} failed (exit $code)" }
    EOT
  }

  depends_on = [null_resource.mcp_server_api]
}
