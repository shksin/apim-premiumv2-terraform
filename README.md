# APIM Premium v2 + Private Endpoint Lockdown — Terraform

End-to-end setup for Azure API Management **Premium v2** with **Internal VNet injection** (Step 1) and a follow-up **management-plane lockdown via Private Endpoint** (Step 1b).

After both steps the service has **no public ingress** — gateway, management API, dev portal, SCM, and configuration endpoints are all reachable only from inside the VNet.

---

## What gets deployed

### Step 1 — APIM with VNet injection ([main.tf](main.tf))

| Resource | Purpose |
|---|---|
| `azurerm_resource_group.rg` | Container for everything |
| `azurerm_virtual_network.vnet` | `10.0.0.0/16` |
| `azurerm_subnet.apim` | `10.0.1.0/24`, delegated to `Microsoft.Web/hostingEnvironments` (PremiumV2 requirement) |
| `azurerm_network_security_group.apim_nsg` | Allows VNet inbound 443, allows outbound to `Storage` / `AzureKeyVault` / `VirtualNetwork`, **denies** outbound to `Internet` |
| `azurerm_private_dns_zone.apim` | `azure-api.net`, linked to the VNet |
| `azapi_resource.apim` | The APIM service (`PremiumV2`, capacity 3, `virtualNetworkType = Internal`) |
| `azurerm_private_dns_a_record.apim_gateway` | Maps `<name>.azure-api.net` → APIM private VIP |

### Step 1b — Management plane lockdown ([step1b_pe_lockdown.tf](step1b_pe_lockdown.tf))

| Resource | Purpose |
|---|---|
| `azurerm_subnet.pe` | `10.0.2.0/27`, no delegation, used for Private Endpoints |
| `azurerm_private_endpoint.apim_mgmt` | PE on APIM with `subresource = Gateway`; auto-registers all hostnames into the existing private DNS zone |
| `azapi_update_resource.apim_disable_public` | PATCH that flips `properties.publicNetworkAccess = "Disabled"` |

---

## Why Step 1b is required

**Step 1 alone does not fully block public access.** Internal VNet injection only removes the **gateway's** public IP. The **management plane** of every APIM instance — the management REST API, the developer portal, the SCM/Git endpoint, and the configuration endpoint — remains reachable over the public internet by default, regardless of `virtualNetworkType`.

After Step 1, querying the resource shows:

```
vnetType            : Internal       ← gateway is private
publicNetworkAccess : Enabled        ← management plane is still public
publicIPs           : []
privateIPs          : ["10.0.1.4"]
```

Anyone on the internet can still hit `https://<apim>.management.azure-api.net`, the developer portal at `https://<apim>.developer.azure-api.net`, and the SCM endpoint. Authentication is required, but the surface is exposed and counts against most "no public ingress" compliance baselines (CIS, Azure Security Benchmark, internal Zero Trust policies).

**Step 1b closes that gap** by:

1. Creating an undelegated subnet for Private Endpoints (the APIM subnet has a `Microsoft.Web/hostingEnvironments` delegation, which is incompatible with PEs).
2. Creating a Private Endpoint with `subresource = Gateway`. This single PE projects **all** APIM hostnames (gateway, management, scm, portal, developer, configuration) onto a NIC inside the VNet, and auto-registers them in the `azure-api.net` private DNS zone.
3. PATCHing `properties.publicNetworkAccess = "Disabled"` on the APIM resource. After this, the management plane is reachable **only** through the Private Endpoint.

### Why it can't be done in a single step

The `publicNetworkAccess = "Disabled"` flag **cannot be set at create time**. APIM rejects it with:

```
ActivateServiceWithPrivateEndpointAccessNotAllowed
```

Microsoft's documented behavior: *"You can disable public network access in an existing API Management instance, not during the deployment process."* It also requires a Private Endpoint to be in place first — otherwise APIM refuses to disable public access because it would orphan the management API.

Order of operations is therefore mandatory and enforced via `depends_on` in Terraform:

1. Create APIM with Internal VNet injection — gateway becomes private, management plane stays public (`publicNetworkAccess=Enabled`).
2. Create the PE subnet + Private Endpoint (`subresource = Gateway`).
3. PATCH `publicNetworkAccess = Disabled` once the PE is `Approved`.

That's why Step 1b is a separate file ([step1b_pe_lockdown.tf](step1b_pe_lockdown.tf)) and uses `azapi_update_resource` rather than baking the flag into the original `azapi_resource.apim` body.

### What Step 1b buys you

| Surface | After Step 1 only | After Step 1b |
|---|---|---|
| Gateway (`*.azure-api.net`) | Private | Private |
| Management API (`*.management.azure-api.net`) | **Public** | Private only |
| Developer portal | **Public** | Private only |
| SCM / configuration endpoints | **Public** | Private only |
| Private Endpoint connections | 0 | 1 (Approved) |
| `publicNetworkAccess` | `Enabled` | **`Disabled`** |

---

## Why these specific design choices

| Choice | Reason |
|---|---|
| `azapi` for the APIM resource | The `azurerm` `api_management` resource does not support the `PremiumV2` SKU. |
| `Microsoft.ApiManagement/service@2024-05-01` | Latest GA API version that supports PremiumV2. |
| `virtualNetworkType = "Internal"` | Removes the public IP from the gateway. `External` would keep one. |
| `capacity = 3` | Required for Availability Zones on PremiumV2 (also enforced by a `validation` block). |
| `zones` set conditionally via `merge()` | Some subscriptions/regions don't expose AZs for PremiumV2 yet. The config falls back gracefully when `availability_zones = []`. |
| Subnet delegation `Microsoft.Web/hostingEnvironments` | Required by the PremiumV2 platform. |
| NSG `DenyInternetOutbound` | Locks down arbitrary outbound; allows only the dependencies APIM actually needs. |
| Private DNS zone `azure-api.net` linked to the VNet | Mandatory for Internal mode — otherwise nothing inside the VNet can resolve the gateway hostname. |
| PE subnet separate from the APIM subnet (`10.0.2.0/27`) | The APIM subnet has a delegation, which is incompatible with Private Endpoints. PEs need an undelegated subnet. |
| PE `subresource_names = ["Gateway"]` | This single subresource exposes **all** APIM hostnames (gateway, management, scm, portal, developer, configuration) over the same PE. |
| `azapi_update_resource` for `publicNetworkAccess` | Decouples the post-create PATCH from the original `azapi_resource` body so the create call doesn't get rejected. |

---

## Prerequisites

- Terraform **>= 1.5** ([install](https://developer.hashicorp.com/terraform/install))
- Azure CLI **>= 2.60** and an authenticated session (`az login`)
- Subscription with the `Microsoft.ApiManagement` provider registered:
  ```powershell
  az provider register --namespace Microsoft.ApiManagement
  ```
- A globally unique APIM name (DNS rule: `<name>.azure-api.net` must be free)
- Permission to create RGs, VNets, NSGs, Private DNS zones, Private Endpoints, and APIM services in the target subscription
- A region where **PremiumV2** is available (e.g. `australiaeast`, `eastus2`, `westus2`, `uksouth`, `swedencentral`)

---

## Configuration

Edit [terraform.tfvars](terraform.tfvars):

```hcl
apim_name          = "apim-premiumv2-ss-26a"      # globally unique
publisher_email    = "you@example.com"
publisher_name     = "Your Name"

# Optional — leave [] if your subscription doesn't expose PremiumV2 AZs
availability_zones = []
```

Other knobs in [variables.tf](variables.tf): `location`, `resource_group_name`, `vnet_address_space`, `apim_subnet_prefix`, `pe_subnet_prefix`.

---

## Deploy

### Step 0 — Init

```powershell
cd apim-premiumv2
terraform init
```

### Step 1 — APIM with VNet injection

```powershell
# Plan only (optional)
terraform plan -target=azapi_resource.apim

# Full apply for Step 1 — the APIM creation alone takes ~20–25 min
terraform apply `
  -target=azurerm_resource_group.rg `
  -target=azurerm_virtual_network.vnet `
  -target=azurerm_subnet.apim `
  -target=azurerm_network_security_group.apim_nsg `
  -target=azurerm_subnet_network_security_group_association.apim_nsg_assoc `
  -target=azurerm_private_dns_zone.apim `
  -target=azurerm_private_dns_zone_virtual_network_link.apim `
  -target=azapi_resource.apim `
  -target=azurerm_private_dns_a_record.apim_gateway `
  -auto-approve
```

Or simply `terraform apply -auto-approve` to do Step 1 + Step 1b in one go (Terraform will order them correctly via `depends_on`).

**Verify Step 1**:

```powershell
$sid = az account show --query id -o tsv
az rest --method get `
  --url "https://management.azure.com/subscriptions/$sid/resourceGroups/rg-apim-premiumv2/providers/Microsoft.ApiManagement/service/$(terraform output -raw apim_resource_id | Split-Path -Leaf)?api-version=2024-05-01" `
  --query "{vnetType:properties.virtualNetworkType, publicNetworkAccess:properties.publicNetworkAccess, publicIPs:properties.publicIPAddresses, privateIPs:properties.privateIPAddresses}" -o json
```

Expected:

```json
{
  "vnetType": "Internal",
  "publicNetworkAccess": "Enabled",   // still public — Step 1b fixes this
  "publicIPs": [],
  "privateIPs": ["10.0.1.4"]
}
```

### Step 1b — Lock down the management plane

```powershell
terraform apply `
  -target=azurerm_subnet.pe `
  -target=azurerm_private_endpoint.apim_mgmt `
  -target=azapi_update_resource.apim_disable_public `
  -auto-approve
```

Takes ~2 min for the PE + ~4 min for the PATCH.

**Verify Step 1b**:

```powershell
$sid = az account show --query id -o tsv
$rid = terraform output -raw apim_resource_id
$apim = az rest --method get --url "https://management.azure.com$rid?api-version=2024-05-01" -o json | ConvertFrom-Json
[pscustomobject]@{
  vnetType            = $apim.properties.virtualNetworkType
  publicNetworkAccess = $apim.properties.publicNetworkAccess
  peCount             = ($apim.properties.privateEndpointConnections | Measure-Object).Count
  peState             = $apim.properties.privateEndpointConnections[0].properties.privateLinkServiceConnectionState.status
} | Format-List
```

Expected:

```
vnetType            : Internal
publicNetworkAccess : Disabled
peCount             : 1
peState             : Approved
```

---

## Resulting network exposure

| Surface | Public internet | VNet (or peered) |
|---|---|---|
| Gateway `*.azure-api.net` | Blocked (no public IP, no public DNS) | Reachable at private VIP via private DNS |
| Management API `*.management.azure-api.net` | Blocked (`publicNetworkAccess=Disabled`) | Reachable via PE NIC IP via private DNS |
| Dev portal / SCM / configuration | Blocked | Reachable via PE NIC IP via private DNS |
| ARM control plane (`management.azure.com/.../service/...`) | Reachable (RBAC-gated, normal ARM) | Reachable |

Outbound from APIM is restricted by the NSG to `Storage`, `AzureKeyVault`, and `VirtualNetwork` only — **no arbitrary public egress**.

---

## Common gotchas

- **`AvailabilityZonesNotSupportedInSku`** at create time → your subscription/region doesn't expose PremiumV2 AZs yet. Set `availability_zones = []` in `terraform.tfvars`.
- **`ServiceSkuActivationThrottled`** → APIM enforces a 60-min cooldown per subscription on PremiumV2 activations. Wait it out.
- **`ActivateServiceWithPrivateEndpointAccessNotAllowed`** at create time → you tried to set `publicNetworkAccess=Disabled` on create. It must be a post-create PATCH after the PE exists. (This is exactly what Step 1b handles.)
- **Cannot resolve `*.azure-api.net` from a peered VNet** → you must link the `azure-api.net` private DNS zone to that VNet too.
- **PE creation fails with subnet error** → the APIM subnet has a delegation, which is incompatible with PEs. The PE goes into the dedicated `snet-apim-pe` subnet, not the APIM subnet.

---

## Destroy

```powershell
terraform destroy -auto-approve
```

APIM destroy takes ~10–20 min. The resource group and all networking are removed cleanly.

---

## References (Microsoft Learn)

**APIM Premium v2 & VNet injection**
- [About API Management v2 tiers](https://learn.microsoft.com/azure/api-management/v2-service-tiers-overview)
- [Use a virtual network with Azure API Management (Premium v2)](https://learn.microsoft.com/azure/api-management/integrate-vnet-outbound)
- [Deploy your API Management instance to a virtual network — internal mode](https://learn.microsoft.com/azure/api-management/api-management-using-with-internal-vnet)
- [Virtual network configuration reference (NSG rules, ports, service tags)](https://learn.microsoft.com/azure/api-management/virtual-network-reference)
- [Subnet delegation — `Microsoft.Web/hostingEnvironments`](https://learn.microsoft.com/azure/virtual-network/subnet-delegation-overview)

**Private Endpoint & public network access**
- [Connect privately to API Management with a Private Endpoint](https://learn.microsoft.com/azure/api-management/private-endpoint)
- [Disable public network access to API Management](https://learn.microsoft.com/azure/api-management/private-endpoint#disable-public-network-access) — documents that this can only be done after creation
- [Azure Private Endpoint overview](https://learn.microsoft.com/azure/private-link/private-endpoint-overview)
- [Private Endpoint DNS configuration](https://learn.microsoft.com/azure/private-link/private-endpoint-dns)

**Availability zones**
- [Availability zone support for API Management](https://learn.microsoft.com/azure/reliability/reliability-api-management) (a.k.a. https://aka.ms/apimaz)

**Terraform providers**
- [`azapi_resource`](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource)
- [`azapi_update_resource`](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/update_resource)
- [`azurerm_private_endpoint`](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint)
- [`azurerm_private_dns_zone`](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone)

**ARM REST reference**
- [`Microsoft.ApiManagement/service` (2024-05-01)](https://learn.microsoft.com/azure/templates/microsoft.apimanagement/service?pivots=deployment-language-arm-template) — schema for `virtualNetworkType`, `virtualNetworkConfiguration`, `publicNetworkAccess`, `zones`

