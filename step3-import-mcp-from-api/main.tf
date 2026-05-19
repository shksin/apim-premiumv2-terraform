# ═══════════════════════════════════════════════════════════════
# Stage 3 — Expose an existing APIM REST API as an MCP server
#
# Pre-req: the source REST API (e.g. `todo`) already exists in
# APIM — imported by step 2 (step2-import-api-with-policies).
#
# Resources created here:
#   1. APIM Backend pointing at the source API's upstream URL
#      (required: MCP API's backendId must reference a Backend entity)
#   2. MCP-type API (type=mcp) — created via `az rest` since the
#      azapi schema doesn't yet cover MCP-specific properties
#   3. One MCP tool per operation in the source API (auto-discovered
#      from the OpenAPI spec used during stage 2 import)
# ═══════════════════════════════════════════════════════════════

locals {
  apim_id = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.ApiManagement/service/${var.apim_name}"

  # Parse the source OpenAPI spec to enumerate every operationId.
  source_openapi = jsondecode(file("${path.module}/${var.source_openapi_path}"))

  # paths.<route>.<method>.operationId  →  flat list of operation IDs.
  source_operation_ids = flatten([
    for path_key, path_obj in local.source_openapi.paths : [
      for method, op in path_obj :
      op.operationId if contains(["get", "put", "post", "delete", "patch", "head", "options"], lower(method)) && can(op.operationId)
    ]
  ])

  # Tool descriptions, keyed by operationId. Prefers summary, then description.
  source_operation_meta = {
    for entry in flatten([
      for path_key, path_obj in local.source_openapi.paths : [
        for method, op in path_obj : {
          op_id   = try(op.operationId, null)
          summary = try(op.summary, try(op.description, op.operationId))
        } if contains(["get", "put", "post", "delete", "patch", "head", "options"], lower(method)) && can(op.operationId)
      ]
    ]) : entry.op_id => entry.summary
  }
}

# ── APIM Backend pointing at the upstream service URL ────────
resource "azapi_resource" "mcp_backend" {
  type      = "Microsoft.ApiManagement/service/backends@2024-05-01"
  name      = var.mcp_backend_name
  parent_id = local.apim_id

  body = {
    properties = {
      url      = var.source_api_backend_url
      protocol = "http"
    }
  }
}

# ── MCP server API + tools (driven via az rest @ 2025-09-01-preview) ──
# Why az rest instead of azapi_resource?
#   1. `type = "mcp"` on Microsoft.ApiManagement/service/apis and the
#      `mcpProperties` block (transportType, endpoints) only exist from
#      api-version 2025-09-01-preview, which azapi's strict schema
#      didn't yet accept at the time this was written.
#   2. The `Microsoft.ApiManagement/service/apis/tools` child resource
#      has no provider coverage at all.
# This is the same call the portal's "Expose an API as an MCP server"
# wizard makes — replace with azapi_resource once provider support lands.
locals {
  mcp_api_ver  = var.mcp_api_version
  mcp_arm_base = "https://management.azure.com${local.apim_id}/apis/${var.mcp_server_api_name}"

  mcp_server_body = jsonencode({
    properties = {
      displayName          = var.mcp_server_api_display_name
      description          = var.mcp_server_api_description
      path                 = var.mcp_server_api_path
      protocols            = ["https"]
      subscriptionRequired = true
      type                 = "mcp"
      backendId            = azapi_resource.mcp_backend.name
      mcpProperties = {
        transportType = var.mcp_server_transport_type
        endpoints     = { message = { uriTemplate = "/mcp" } }
      }
    }
  })

  mcp_tool_bodies = {
    for op_id in local.source_operation_ids :
    op_id => jsonencode({
      properties = {
        displayName = op_id
        description = lookup(local.source_operation_meta, op_id, op_id)
        operationId = "/apis/${var.source_api_name}/operations/${op_id}"
      }
    })
  }
}

resource "null_resource" "mcp_server_api" {
  triggers = {
    body    = local.mcp_server_body
    api_ver = local.mcp_api_ver
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
        --url "${local.mcp_arm_base}?api-version=${local.mcp_api_ver}" `
        --body "@$tmp" `
        --headers "Content-Type=application/json" `
        --only-show-errors -o none
      $code = $LASTEXITCODE
      Remove-Item $tmp -Force
      if ($code -ne 0) { throw "az rest PUT ${var.mcp_server_api_name} failed (exit $code)" }
    EOT
  }

  depends_on = [azapi_resource.mcp_backend]
}

resource "null_resource" "mcp_tool" {
  for_each = local.mcp_tool_bodies

  triggers = {
    body    = each.value
    api_ver = local.mcp_api_ver
  }

  # ARM occasionally returns 502 Bad Gateway under load — retry up to 5×
  # with a 4s backoff so transient gateway errors don't fail the apply.
  provisioner "local-exec" {
    interpreter = ["pwsh", "-NoProfile", "-Command"]
    command     = <<-EOT
      $body = @'
      ${each.value}
      '@
      $tmp = New-TemporaryFile
      Set-Content -Path $tmp -Value $body -Encoding utf8
      $ok = $false
      for ($i = 1; $i -le 5; $i++) {
        az rest --method put `
          --url "${local.mcp_arm_base}/tools/${each.key}?api-version=${local.mcp_api_ver}" `
          --body "@$tmp" `
          --headers "Content-Type=application/json" `
          --only-show-errors -o none 2>$null
        if ($LASTEXITCODE -eq 0) { $ok = $true; break }
        Write-Host "PUT tool ${each.key} attempt $i failed; retrying..."
        Start-Sleep -Seconds 4
      }
      Remove-Item $tmp -Force
      if (-not $ok) { throw "az rest PUT tool ${each.key} failed after 5 attempts" }
    EOT
  }

  depends_on = [null_resource.mcp_server_api]
}
