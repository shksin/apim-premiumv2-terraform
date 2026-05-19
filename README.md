# APIM Premium v2 — Terraform deployment

Three Terraform modules with their own state. Run them in order.

```
step1-apim-premiumv2-private/          # 1. Platform: APIM Premium v2 + VNet + management lockdown
step2-import-api-with-policies/        # 2. Import a REST API into APIM + apply policy
step3-import-mcp-from-api/             # 3. Project the imported API as an MCP server (all operations exposed as tools)
```

## What you need before you start

You only need one thing of your own: an **existing backend service URL** (e.g. an Azure App Service, Container App, or any HTTPS endpoint) that hosts the REST API you want to publish through APIM. That URL goes into:

- step 2 as `api_backend_url` — set as the APIM API's `serviceUrl`
- step 3 as `source_api_backend_url` — used to create the APIM Backend that the MCP server forwards to

Everything else (resource group, VNet, APIM, private endpoints, the imported API, and the MCP projection) is created by these modules. You also supply your own `open-api-spec/open-api-spec.json` describing the backend's API surface, and optionally a `policy.xml` for step 2.

**Run order:**

1. `step1-apim-premiumv2-private` (Terraform) — creates the resource group, VNet, APIM Premium v2, private DNS, management Private Endpoint.
2. `step2-import-api-with-policies` (Terraform) — imports your REST API into APIM from `open-api-spec/open-api-spec.json`; set `api_backend_url` to your backend.
3. `step3-import-mcp-from-api` (Terraform) — projects the imported API as an MCP-type API, exposing each operation as an MCP tool.

> If your backend lives in a private VNet, make sure APIM's VNet is peered (or otherwise routable) to it before running step 2.

---

## Prerequisite: Terraform state backend

Each module persists its Terraform state to an Azure Storage blob via the `azurerm` backend. This is what lets you:

- **Re-run safely from any machine / CI agent** — state isn't trapped in someone's local folder.
- **Run the three modules independently** — each module writes a separate `*.tfstate` blob (with its own lease/lock), so 2a and 2b can be applied in parallel without stepping on each other or on module 1.
- **Avoid losing state** — local `terraform.tfstate` is easy to delete or forget to check in; the storage account is durable and versioned.

All three modules declare the remote backend inline in their `providers.tf`. The values are placeholders (`xxx`) — **before running `terraform init`, edit the `backend "azurerm"` block in each module's `providers.tf`** and fill in `resource_group_name`, `storage_account_name`, `container_name`, and `key`. Use a **distinct `key`** per module (e.g. `step1-apim-premiumv2-private.tfstate`, `step2-import-api-with-policies.tfstate`, `step3-import-mcp-from-api.tfstate`) so each module gets its own state blob.

> **Why not use variables here?** Terraform does not allow variables, locals, or any interpolation inside a `backend` block — values must be literal. The backend is initialized before variables are evaluated. The only alternatives are `-backend-config=key=value` flags or a `-backend-config=*.hcl` file passed to `terraform init`, which we deliberately removed in favour of keeping the settings in source.

### Option A — Use an existing storage account

1. Update `resource_group_name`, `storage_account_name`, `container_name` in each module's `providers.tf` `backend "azurerm"` block.
2. Make sure the identity running `terraform init` / `apply` has **Storage Blob Data Contributor** on the storage account (the backend uses Azure AD auth).
3. The container must already exist; create it once if needed:

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

## Passing variables to Terraform

Each module declares its inputs in `variables.tf` and ships a `terraform.tfvars.example`. There are several ways to supply values — use whichever fits your workflow:

| Method                          | When to use                                                                                  |
| ------------------------------- | -------------------------------------------------------------------------------------------- |
| `terraform.tfvars` file         | **Default for local runs.** Copy `terraform.tfvars.example` → `terraform.tfvars`, then edit. Auto-loaded by Terraform. **Gitignored.** |
| `*.auto.tfvars` files           | Same auto-loading behaviour; useful when you want to split values across multiple files.     |
| `-var-file=path.tfvars`         | Explicitly point at a tfvars file. Handy for per-environment files (`dev.tfvars`, `prod.tfvars`). |
| `-var "name=value"`             | One-off overrides on the CLI.                                                                |
| `TF_VAR_<name>` env vars        | CI / pipeline-friendly. Example: `$env:TF_VAR_apim_name = "apim-foo"`.                       |
| Interactive prompt              | If a required variable has no value supplied, Terraform will prompt at `plan` / `apply`.     |

**Recommended flow:**

```pwsh
cd <step-folder>
cp terraform.tfvars.example terraform.tfvars   # then edit values
terraform init
terraform plan      # review changes
terraform apply
```

**CI / non-interactive:** prefer `TF_VAR_*` env vars (or `-var-file`) so secrets/values aren't checked into the repo:

```pwsh
$env:TF_VAR_subscription_id    = (az account show --query id -o tsv)
$env:TF_VAR_resource_group_name = "rg-apim-premiumv2"
$env:TF_VAR_apim_name          = "apim-premiumv2-foo"
terraform apply -auto-approve
```

> `terraform.tfvars`, `*.auto.tfvars`, and `*.tfstate*` are all gitignored. Only `terraform.tfvars.example` is checked in.

---

## 1. `step1-apim-premiumv2-private`

Creates the resource group, VNet, NSG, private DNS zone, the APIM Premium v2 instance (Internal VNet injection), the management-plane Private Endpoint, and disables public network access. Expect ~30–45 min for the initial deploy.

### Required variables

| Variable              | Description                                  |
| --------------------- | -------------------------------------------- |
| `subscription_id`     | Azure subscription ID                        |
| `resource_group_name` | Name of the resource group to create         |
| `apim_name`           | Globally unique APIM instance name           |
| `publisher_email`     | Publisher email for the APIM instance        |
| `publisher_name`      | Publisher display name                       |

### Optional variables (with defaults)

| Variable              | Default            |
| --------------------- | ------------------ |
| `location`            | `australiaeast`    |
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
cd step1-apim-premiumv2-private
cp terraform.tfvars.example terraform.tfvars   # then edit

terraform init
terraform apply
```

### Outputs

`subscription_id`, `resource_group_name`, `apim_name`, `apim_resource_id`, `apim_gateway_url`, `apim_private_ip`, `vnet_id`, `vnet_name`, `apim_subnet_id`, `private_dns_zone_id`.

---

## 2a. `step2-import-api-with-policies`

Imports a REST API into APIM from a **consumer-supplied** OpenAPI 3.x JSON
spec and applies an API-level policy. The API's `serviceUrl` points at
the consumer's existing backend (e.g. App Service).

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

Note: because module 1 disables APIM public network access, the MCP endpoint (`https://{apim}.azure-api.net/todo-mcp/mcp`) is reachable only from inside the VNet (or via a peered network / VPN / Private Endpoint).

---

