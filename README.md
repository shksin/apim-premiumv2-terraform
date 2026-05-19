# APIM Premium v2 — staged Terraform deployment

Three **independent** Terraform root modules. Each has its own state file in
Azure Storage, its own variables, and is meant to run in its own pipeline.

```
apim-premiumv2-private/         # platform: APIM + VNet + management lockdown
import-api-with-policies/       # import Petstore REST API + policy
import-mcp-from-app-service/    # import REST API from App Service + expose as MCP server
```

## Coupling model

`import-api-with-policies` and `import-mcp-from-app-service` do **not** read
`apim-premiumv2-private`'s state. They locate APIM by constructing its ARM ID
deterministically from inputs:

```hcl
locals {
  apim_id = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.ApiManagement/service/${var.apim_name}"
}
```

So in CI/CD you just pass `subscription_id`, `resource_group_name`, `apim_name`
as variables to the downstream modules (typically captured from
`apim-premiumv2-private`'s `terraform output -json`).

## One-time prerequisites

1. **Azure Storage account for Terraform state** (one storage account, one
   container, three different keys):
   ```pwsh
   az group create -n rg-tfstate -l australiaeast
   az storage account create -n sttfstateapimpremv2 -g rg-tfstate -l australiaeast --sku Standard_LRS
   az storage container create -n tfstate --account-name sttfstateapimpremv2 --auth-mode login
   ```
2. **Service principal / managed identity** with Contributor (or finer) on the
   target subscription + Storage Blob Data Contributor on the state container.

## Per-module CI/CD pattern

For each module the pipeline does the same 5 steps.

```pwsh
cd <module-folder>

# 1. init (partial backend — values come from CI secrets, NOT committed)
terraform init `
  -backend-config="resource_group_name=$env:TFSTATE_RG" `
  -backend-config="storage_account_name=$env:TFSTATE_SA" `
  -backend-config="container_name=tfstate" `
  -backend-config="key=<module>.tfstate"

# 2. plan
terraform plan -out tfplan -var-file=tfvars/$env:ENVIRONMENT.tfvars

# 3. (optional) gate / approval

# 4. apply
terraform apply -auto-approve tfplan

# 5. export outputs for downstream pipelines
terraform output -json | Out-File outputs.json
```

## Pipeline dependencies

```
┌────────────────────────────────┐
│  apim-premiumv2-private        │   creates APIM, VNet, lockdown
│  outputs: apim_name, rg, sub   │
└────────────────────────────────┘
              │
              ▼ (apim_name, resource_group_name, subscription_id)
┌────────────────────────────────┐    ┌───────────────────────────────────┐
│  import-api-with-policies      │    │  create-mcp-appservice.ps1        │
│  inputs: APIM coords           │    │  (out-of-band script; creates the │
│                                │    │   private App Service + PE)       │
└────────────────────────────────┘    └───────────────────────────────────┘
                                                  │
                                                  ▼ (app_service_name + RG)
                                     ┌───────────────────────────────────┐
                                     │  import-mcp-from-app-service      │
                                     │  inputs: APIM coords + AppSvc     │
                                     └───────────────────────────────────┘
```

`import-api-with-policies` and `import-mcp-from-app-service` are independent —
they can run in any order (or in parallel) after `apim-premiumv2-private`.

## `apim-premiumv2-private`

**Required inputs:** `subscription_id`, `apim_name`, `publisher_email`,
`publisher_name`. Optional: `location`, `resource_group_name`, `vnet_*`,
`apim_subnet_*`, `pe_subnet_*`, `availability_zones`, `apim_sku_capacity`.

**Outputs (consumed by downstream modules):** `subscription_id`,
`resource_group_name`, `apim_name`, `apim_resource_id`, `apim_gateway_url`,
`apim_private_ip`, `vnet_id`, `vnet_name`, `apim_subnet_id`,
`private_dns_zone_id`.

Expect 30–45 minutes for the initial APIM Premium v2 deployment.

## `import-api-with-policies`

**Required inputs:**
- `subscription_id`
- `resource_group_name` ← from `apim-premiumv2-private` output
- `apim_name` ← from `apim-premiumv2-private` output

Bundles `petstore-openapi.json` + `policy.xml`. Override with
`openapi_spec_path` / `policy_xml_path` if you keep the spec elsewhere.

## `import-mcp-from-app-service`

**Required inputs:**
- `subscription_id`
- `resource_group_name`
- `apim_name`
- `mcp_app_service_name`
- `mcp_app_service_resource_group`

**Run order:**
1. After `apim-premiumv2-private` completes, run
   `../create-appservice/create-mcp-appservice.ps1` to provision the private
   App Service. (That folder is git-ignored — it's an out-of-band bootstrap
   script, not part of the Terraform pipeline.) The script prints the chosen
   App Service name + RG — capture those and feed them in as variables.
2. Then `terraform apply`.

The MCP server projection + tools are created via `az rest` against API version
`2025-09-01-preview` (the azapi provider's schema doesn't yet recognize
`type=mcp`). The CI agent must therefore have:
- Azure CLI installed
- PowerShell 7+
- Logged in to Azure (`az login` / service-principal login)

## Local-vs-CI tfvars

`terraform.tfvars.example` in each folder shows the shape. In a real pipeline
you'll typically:
- Keep non-secret values in `tfvars/<env>.tfvars` checked into the repo, OR
- Pass them inline:
  ```pwsh
  terraform apply `
    -var "subscription_id=$env:ARM_SUBSCRIPTION_ID" `
    -var "apim_name=$env:APIM_NAME" `
    -var "resource_group_name=$env:RG_NAME"
  ```

## Re-running a module

All resources are idempotent. The `null_resource` provisioners in
`import-mcp-from-app-service` use `triggers` so they only re-execute when the
request body / API version changes. You can re-apply any module at any time
without affecting the others.
