# ═══════════════════════════════════════════════════════════════
# Step 1 — APIM Premium v2 with VNet Injection (Internal mode)
#
# Creates:
#   - Resource group
#   - VNet + APIM subnet (delegated to Microsoft.Web/hostingEnvironments)
#   - NSG (allows APIM dependencies, denies all internet outbound)
#   - Private DNS zone (azure-api.net) linked to the VNet
#   - APIM Premium v2 instance (Internal VNet injection, public access disabled)
#   - Private DNS A record mapping gateway hostname to APIM private VIP
# ═══════════════════════════════════════════════════════════════

# ── Resource Group ───────────────────────────────────────────
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

# ── VNet ─────────────────────────────────────────────────────
resource "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = [var.vnet_address_space]
}

# ── APIM Subnet ──────────────────────────────────────────────
# Premium v2 VNet injection requirements:
#   - Delegation to Microsoft.Web/hostingEnvironments
#   - Minimum /27, recommended /24
#   - Dedicated to a single APIM instance
resource "azurerm_subnet" "apim" {
  name                 = var.apim_subnet_name
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.apim_subnet_prefix]

  delegation {
    name = "apim-delegation"
    service_delegation {
      name = "Microsoft.Web/hostingEnvironments"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/action"
      ]
    }
  }
}

# ── NSG ──────────────────────────────────────────────────────
# Required rules for Premium v2 internal VNet injection.
# Allows APIM hard dependencies (Storage, Key Vault) and VNet-internal
# traffic. Denies all internet outbound — no public egress.
resource "azurerm_network_security_group" "apim_nsg" {
  name                = "nsg-apim"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  # ── Inbound ──────────────────────────────────────────────
  security_rule {
    name                       = "AllowVnetInboundHTTPS"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  # ── Outbound ─────────────────────────────────────────────
  security_rule {
    name                       = "AllowStorageOutbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "Storage"
  }

  security_rule {
    name                       = "AllowKeyVaultOutbound"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureKeyVault"
  }

  security_rule {
    name                       = "AllowVnetOutbound"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "DenyInternetOutbound"
    priority                   = 1000
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }
}

resource "azurerm_subnet_network_security_group_association" "apim_nsg_assoc" {
  subnet_id                 = azurerm_subnet.apim.id
  network_security_group_id = azurerm_network_security_group.apim_nsg.id
}

# ── Private DNS Zone ─────────────────────────────────────────
# Mandatory for Internal VNet injection — APIM has no public DNS entry.
resource "azurerm_private_dns_zone" "apim" {
  name                = "azure-api.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "apim" {
  name                  = "apim-dns-link"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.apim.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  registration_enabled  = false
}

# ── APIM Premium v2 ──────────────────────────────────────────
# Uses azapi — azurerm does not support PremiumV2 SKU.
# API version 2024-05-01 is the latest GA that supports PremiumV2.
#
# VNet injection is immutable — cannot be changed after deployment.
# To change VNet settings you must destroy and redeploy.
resource "azapi_resource" "apim" {
  type      = "Microsoft.ApiManagement/service@2024-05-01"
  name      = var.apim_name
  parent_id = azurerm_resource_group.rg.id
  location  = azurerm_resource_group.rg.location

  body = merge({
    sku = {
      name     = "PremiumV2"
      capacity = var.apim_sku_capacity
    }
    properties = {
      publisherEmail = var.publisher_email
      publisherName  = var.publisher_name

      # Internal = private inbound only — gateway not reachable from internet
      virtualNetworkType = "Internal"
      virtualNetworkConfiguration = {
        subnetResourceId = azurerm_subnet.apim.id
      }

      # Note: publicNetworkAccess cannot be "Disabled" at creation time
      # (APIM rejects with ActivateServiceWithPrivateEndpointAccessNotAllowed).
      # Leave as default (Enabled) at create; disable post-create via a
      # separate update or portal if you also want to lock the management plane.
    }
    },
    # Availability Zones require capacity >= 3 on PremiumV2
    var.apim_sku_capacity >= 3 && length(var.availability_zones) > 0 ? { zones = var.availability_zones } : {}
  )

  depends_on = [
    azurerm_subnet_network_security_group_association.apim_nsg_assoc,
    azurerm_private_dns_zone_virtual_network_link.apim
  ]

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }
}

# ── Private DNS A Record ─────────────────────────────────────
# Maps the gateway hostname to the APIM private VIP so that
# consumers within the VNet (or peered VNets) can resolve it.
resource "azurerm_private_dns_a_record" "apim_gateway" {
  name                = var.apim_name
  zone_name           = azurerm_private_dns_zone.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  ttl                 = 300
  records             = [azapi_resource.apim.output.properties.privateIPAddresses[0]]
}
