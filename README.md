# APIM Premium v2 — Terraform deployment

Three independent Terraform modules. Run them in order. Each has its own state.

```
apim-premiumv2-private/         # 1. Platform: APIM Premium v2 + VNet + management lockdown
import-api-with-policies/       # 2a. Import a sample Petstore REST API + apply policy (swap in your own OpenAPI spec)
import-mcp-from-app-service/    # 2b. Import REST API from App Service + expose as MCP server
```

Steps 2a and 2b are independent — run either or both, in any order. Module 2b assumes a private App Service already exists in the APIM VNet.

---

## Prerequisite: Terraform state backend

Each module persists its Terraform state to an Azure Storage blob via the `azurerm` backend. This is what lets you:

- **Re-run safely from any machine / CI agent** — state isn't trapped in someone's local folder.
- **Run the three modules independently** — each module writes a separate `*.tfstate` blob (with its own lease/lock), so 2a and 2b can be applied in parallel without stepping on each other or on module 1.
- **Avoid losing state** — local `terraform.tfstate` is easy to delete or forget to check in; the storage account is durable and versioned.

All three modules use a partial backend config, so you supply the storage account at `terraform init` time. Each module's `backend.hcl.example` shows the shape:

```hcl
resource_group_name  = "rg-tfstate"
storage_account_name = "sttfstateapimpremv2"
container_name       = "tfstate"
key                  = "<module-name>.tfstate"   # unique per module
```

### Option A — Use an existing storage account

If you already have a Terraform state storage account, just point each module's `backend.hcl` at it:

1. Copy `backend.hcl.example` to `backend.hcl` in the module folder.
2. Set `resource_group_name`, `storage_account_name`, `container_name` to your existing values.
3. Leave `key` as-is (or pick your own) — just make sure each of the three modules uses a **different** `key`, e.g. `apim-premiumv2-private.tfstate`, `import-api-with-policies.tfstate`, `import-mcp-from-app-service.tfstate`.
4. Make sure the identity running `terraform init` / `apply` has **Storage Blob Data Contributor** on the storage account (the backend uses Azure AD auth by default).
5. The container must already exist; create it once if needed:

   ```pwsh
   az storage container create -n <container> --account-name <storage-account> --auth-mode login
   ```

### Option B — Create a new storage account

```pwsh
az group create -n rg-tfstate -l australiaeast
az storage account create -n sttfstateapimpremv2 -g rg-tfstate -l australiaeast --sku Standard_LRS
az storage container create -n tfstate --account-name sttfstateapimpremv2 --auth-mode login
```

Storage account names must be globally unique and 3–24 lowercase alphanumeric characters — pick your own if `sttfstateapimpremv2` is taken.

---

## 1. `apim-premiumv2-private`

Creates the resource group, VNet, NSG, private DNS zone, the APIM Premium v2 instance (Internal VNet injection), the management-plane Private Endpoint, and disables public network access. Expect ~30–45 min for the initial deploy.

### Required variables

| Variable          | Description                                  |
| ----------------- | -------------------------------------------- |
| `subscription_id` | Azure subscription ID                        |
| `apim_name`       | Globally unique APIM instance name           |
| `publisher_email` | Publisher email for the APIM instance        |
| `publisher_name`  | Publisher display name                       |

### Optional variables (with defaults)

| Variable              | Default            |
| --------------------- | ------------------ |
| `location`            | `australiaeast`    |
| `resource_group_name` | `rg-apim-premiumv2` |
| `apim_sku_capacity`   | `3`                |
| `availability_zones`  | `["1","2","3"]`    |
| `vnet_name`           | `vnet-apim`        |
| `vnet_address_space`  | `10.0.0.0/16`      |
| `apim_subnet_name`    | `snet-apim`        |
| `apim_subnet_prefix`  | `10.0.1.0/24`      |
| `pe_subnet_name`      | `snet-apim-pe`     |
| `pe_subnet_prefix`    | `10.0.2.0/27`      |

### Run

```pwsh
cd apim-premiumv2-private
cp terraform.tfvars.example terraform.tfvars   # then edit
cp backend.hcl.example backend.hcl             # then edit

terraform init -backend-config=backend.hcl
terraform apply
```

### Outputs

`subscription_id`, `resource_group_name`, `apim_name`, `apim_resource_id`, `apim_gateway_url`, `apim_private_ip`, `vnet_id`, `vnet_name`, `apim_subnet_id`, `private_dns_zone_id`.

---

## 2a. `import-api-with-policies`

Imports a **sample Petstore** OpenAPI spec into APIM as a REST API and applies a rate-limit + correlation-ID policy. The bundled `petstore-openapi.json` is just an example — replace it with your own OpenAPI spec (or point `openapi_spec_path` at a different file) to import your real API.

### Required variables

| Variable              | Description                                                  |
| --------------------- | ------------------------------------------------------------ |
| `subscription_id`     | Same subscription as the APIM instance                       |
| `resource_group_name` | RG containing the APIM instance (from module 1)              |
| `apim_name`           | APIM instance name (from module 1)                           |

### Optional variables

| Variable                    | Default                                              |
| --------------------------- | ---------------------------------------------------- |
| `petstore_api_name`         | `petstore`                                           |
| `petstore_api_path`         | `petstore` → `https://{apim}.azure-api.net/petstore` |
| `petstore_api_display_name` | `Petstore API`                                       |
| `petstore_api_description`  | _(see variables.tf)_                                 |
| `openapi_spec_path`         | `petstore-openapi.json` (bundled)                    |
| `policy_xml_path`           | `policy.xml` (bundled)                               |

### Run

```pwsh
cd import-api-with-policies
cp terraform.tfvars.example terraform.tfvars   # then edit (subscription_id, resource_group_name, apim_name)
cp backend.hcl.example backend.hcl             # then edit

terraform init -backend-config=backend.hcl
terraform apply
```

### Outputs

`petstore_api_id`, `petstore_api_url`.

---

## 2b. `import-mcp-from-app-service`

Imports an App Service's REST API into APIM, then projects it as an MCP-type API with selected operations exposed as MCP tools.

**Prerequisite:** An App Service exposing the operations you list in `mcp_tools`.

> **Note:** APIM must have network line of sight to the App Service. Since module 1 deploys APIM in Internal VNet mode, the App Service needs to be reachable from the APIM subnet — typically via a Private Endpoint in the same VNet (or a peered VNet) with the `privatelink.azurewebsites.net` private DNS zone linked so APIM resolves the App Service hostname to its private IP.

### Required variables

| Variable                         | Description                                       |
| -------------------------------- | ------------------------------------------------- |
| `subscription_id`                | Same subscription as the APIM instance            |
| `resource_group_name`            | RG containing the APIM instance (from module 1)   |
| `apim_name`                      | APIM instance name (from module 1)                |
| `mcp_app_service_name`           | Name of the App Service                           |
| `mcp_app_service_resource_group` | RG of the App Service (usually same as APIM's RG) |

### Optional variables

| Variable                      | Default                                                  |
| ----------------------------- | -------------------------------------------------------- |
| `mcp_rest_api_name`           | `mcp-rest`                                               |
| `mcp_rest_api_path`           | `mcp-rest` → `https://{apim}.azure-api.net/mcp-rest`     |
| `mcp_rest_api_display_name`   | `MCP REST Backend`                                       |
| `mcp_server_api_name`         | `mcp-rest-mcp`                                           |
| `mcp_server_api_path`         | `mcp-server` → `https://{apim}.azure-api.net/mcp-server` |
| `mcp_server_api_display_name` | `MCP REST Backend (MCP server)`                          |
| `mcp_server_transport_type`   | `streamable` (only supported value)                      |
| `mcp_tools_api_version`       | `2025-09-01-preview`                                     |
| `mcp_tools`                   | Map of `{ description, operation_id, display_name? }` keyed by tool name. Defaults: `hello`, `echo`. |
| `openapi_spec_path`           | `mcp-rest-openapi.json` (bundled)                        |
| `policy_xml_path`             | `policy.xml` (bundled)                                   |

### Run

```pwsh
cd import-mcp-from-app-service
cp terraform.tfvars.example terraform.tfvars   # then edit
cp backend.hcl.example backend.hcl             # then edit

terraform init -backend-config=backend.hcl
terraform apply
```

Requires Azure CLI + PowerShell 7 + `az login` on the machine running `terraform apply` (the MCP server + tools are created via `az rest` because the azapi provider's schema doesn't yet cover `type=mcp`).

### Outputs

`mcp_rest_api_id`, `mcp_rest_api_url`, `mcp_server_url`, `mcp_server_endpoint`, `mcp_backend_hostname`.

---

