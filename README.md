# APIM Premium v2 — Terraform deployment




## Prerequisite: To run Terraform scripts

Each module persists its Terraform state to an Azure Storage blob via the `azurerm` backend:
1. Use an existing Storage Account or create a new one to store Terraform state
2. Make sure the identity running `terraform init` / `apply` has **Storage Blob Data Contributor** on the storage account (the backend uses Azure AD auth).
   
3. Each step  declare the remote backend inline in their `providers.tf`. The values are placeholders (`xxx`) — **before running `terraform init`, edit the `backend "azurerm"` block in each module's `providers.tf`** and fill in `resource_group_name`, `storage_account_name`, `container_name`, and `key`. Use a **distinct `key`** per module (e.g. `step1-apim-premiumv2-private.tfstate`, `step2-import-api-with-policies.tfstate`, `step3-import-mcp-from-api.tfstate`) so each module gets its own state blob.



---

## 1. `step1-apim-premiumv2-private`

### Prerequisite

**Pre-existing networking** in the target subscription / region:
   - A resource group
   - A VNet with **three subnets**:
     - APIM injection subnet (e.g. `snet-apim`, /24 recommended) — must have an NSG with the rules required by APIM Premium v2 ([reference](https://learn.microsoft.com/en-us/azure/api-management/inject-vnet-v2)).
     - Private Endpoint subnet (e.g. `snet-apim-pe`, /27)
   - A private DNS zone `azure-api.net` linked to that VNet

Deploys APIM Premium v2 with Internal VNet injection and a management-plane Private Endpoint via the [Azure Verified Module](https://registry.terraform.io/modules/Azure/avm-res-apimanagement-service/azurerm) `Azure/avm-res-apimanagement-service/azurerm`. Consumes your pre-existing RG, VNet, subnets, and `azure-api.net` private DNS zone via data sources.

> **Two-apply process.** Azure rejects `publicNetworkAccess=Disabled` at *create* time for APIM with Internal VNet injection — it is only accepted on *update*. So step 1 runs `terraform apply` twice: first without setting `public_network_access_enabled` (the AVM module's default applies, leaving public access enabled at create time), then again with `-var=public_network_access_enabled=false` to lock down the management plane.
>
> Expect ~20–25 min for the create, ~5 min for the lockdown.

### Required variables

| Variable                | Description                                          |
| ----------------------- | ---------------------------------------------------- |
| `subscription_id`       | Azure subscription ID                                |
| `location`              | Azure region (must match the pre-existing network)   |
| `resource_group_name`   | Existing RG containing the VNet                      |
| `apim_name`             | Globally unique APIM instance name                   |
| `publisher_email`       | Publisher email for the APIM instance                |
| `publisher_name`        | Publisher display name                               |
| `vnet_name`             | Name of the existing VNet (e.g. `vnet-apim`)         |
| `apim_subnet_name`      | APIM injection subnet name (e.g. `snet-apim`)        |
| `pe_subnet_name`        | Private Endpoint subnet name (e.g. `snet-apim-pe`)   |
| `private_dns_zone_name` | Private DNS zone for APIM (e.g. `azure-api.net`)     |

### Optional variables (with defaults)

| Variable                        | Default                                              |
| ------------------------------- | ---------------------------------------------------- |
| `apim_sku_capacity`             | `3`                                                  |
| `availability_zones`            | `["1","2","3"]`                                      |
| `public_network_access_enabled` | unset (AVM module default — only set on pass 2)      |

### Run

```pwsh
cd step1-apim-premiumv2-private
cp terraform.tfvars.example terraform.tfvars   # then edit

terraform init

# Pass 1 — create APIM (public access enabled by Azure requirement)
terraform apply -auto-approve

# Pass 2 — lock down the management plane to the Private Endpoint
terraform apply -auto-approve -var="public_network_access_enabled=false"
```

### Outputs

`subscription_id`, `resource_group_name`, `apim_name`, `apim_resource_id`, `apim_gateway_url`, `apim_private_ip`, `vnet_id`, `vnet_name`, `apim_subnet_id`, `private_dns_zone_id`.

---

## 2. `step2-import-api-with-policies`

Imports a REST API into APIM from an OpenAPI 3.x spec and applies an API-level policy. The API's `serviceUrl` points at
an existing backend (e.g. App Service).

### Prerequisite

1. An **existing backend service URL** (e.g. an Azure App Service) hosting the REST API you want to publish through APIM. That URL goes into:
   - step 2 as `api_backend_url` — set as the APIM API's `serviceUrl`
   - step 3 as `source_api_backend_url` — used to create the APIM Backend that the MCP server forwards to

You also supply your own `open-api-spec/open-api-spec.json` describing the backend's API surface, and optionally a `policy.xml` for step 2.


> If your backend lives in a private VNet, make sure APIM's VNet is peered (or otherwise routable) to it before running step 2.

---

A sample OpenAPI spec ships at the repo root in `open-api-spec/open-api-spec.json`
(shared with step 3) and a sample policy at `step2-import-api-with-policies/policy.xml`
— replace both with your own.

### Required variables

| Variable              | Description                                                          |
| --------------------- | -------------------------------------------------------------------- |
| `subscription_id`     | Same subscription as the APIM instance                               |
| `resource_group_name` | RG containing the APIM instance (from step 1)                        |
| `apim_name`           | APIM instance name (from step 1)                                     |
| `api_name`            | APIM resource id segment for the API (e.g. `todo`)                   |
| `api_path`            | URL suffix — `https://{apim}.azure-api.net/{api_path}`               |
| `api_display_name`    | Portal display name                                                  |
| `api_backend_url`     | Upstream service URL (e.g. `https://<app>.azurewebsites.net`)        |

### Optional variables

| Variable                    | Default                                  |
| --------------------------- | ---------------------------------------- |
| `api_description`           | `""`                                     |
| `api_protocols`             | `["https"]`                              |
| `api_subscription_required` | `true`                                   |
| `openapi_spec_path`         | `../open-api-spec/open-api-spec.json`    |
| `policy_xml_path`           | `policy.xml`                             |

### Run

```pwsh
cd step2-import-api-with-policies
cp terraform.tfvars.example terraform.tfvars   # then edit (subscription_id, resource_group_name, apim_name, api_*, paths)

terraform init
terraform apply
```

### Outputs

`api_id`, `api_url`.

---

## 2b. `step3-import-mcp-from-api`

Projects an existing REST API in APIM as an **MCP-type API**, with every
operation in the source OpenAPI spec exposed as an MCP tool. The module
creates an APIM Backend pointing at the upstream URL and wires the MCP
API to it.

**Prerequisite:** the source REST API must already exist in APIM
(typically imported by step 2).

### How it works

1. Creates an APIM **Backend** resource (`mcp_backend_name`) pointing at `source_api_backend_url`.
2. Creates an **MCP-type API** (`mcp_server_api_name`) referencing that backend, with `transportType=streamable` and endpoint `/mcp`.
3. Parses `source_openapi_path` to enumerate every `operationId`, then creates one **MCP tool** per operation, each tool's `operationId` pointing at `/apis/<source_api_name>/operations/<op>`.

MCP-specific resources are PUT via `az rest @ 2025-09-01-preview` (wrapped in `null_resource` with a 5× retry on transient ARM 502s) since the azapi schema doesn't yet cover `type=mcp`.

### Required variables

| Variable                      | Description                                                                       |
| ----------------------------- | --------------------------------------------------------------------------------- |
| `subscription_id`             | Same subscription as the APIM instance                                            |
| `resource_group_name`         | RG containing the APIM instance (from step 1)                                     |
| `apim_name`                   | APIM instance name (from step 1)                                                  |
| `source_api_name`             | APIM resource name of the existing REST API to project                            |
| `source_api_backend_url`      | Upstream URL the MCP server forwards to                                           |
| `mcp_server_api_name`         | APIM resource name for the MCP-type API                                           |
| `mcp_backend_name`            | APIM Backend resource name                                                        |
| `mcp_server_api_path`         | URL suffix — `https://{apim}.azure-api.net/{mcp_server_api_path}`                 |
| `mcp_server_api_display_name` | Portal display name                                                               |

### Optional variables

| Variable                      | Default                                  |
| ----------------------------- | ---------------------------------------- |
| `source_openapi_path`         | `../open-api-spec/open-api-spec.json`    |
| `mcp_server_api_description`  | `""`                                     |
| `mcp_server_transport_type`   | `streamable` (only supported value)      |
| `mcp_api_version`             | `2025-09-01-preview`                     |

### Run

```pwsh
cd step3-import-mcp-from-api
cp terraform.tfvars.example terraform.tfvars   # then edit

terraform init
terraform apply
```

Requires Azure CLI + PowerShell 7 + `az login` on the machine running `terraform apply`.

### Outputs

`mcp_server_api_id`, `mcp_server_url`, `mcp_server_endpoint`, `mcp_backend_url`, `mcp_tool_count`, `mcp_tool_names`.

**Note**: because module 1's second apply disables APIM public network access, the MCP endpoint (`https://{apim}.azure-api.net/todo-mcp/mcp`) is reachable only from inside the VNet (or via a peered network / VPN / Private Endpoint).

---

