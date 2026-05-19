# ═══════════════════════════════════════════════════════════════
# Stage 1 — APIM Premium v2 with VNet Injection (Internal mode)
#                    + Management plane lockdown
#
# Resources:
#   - Resource group
#   - VNet + APIM subnet (delegated to Microsoft.Web/hostingEnvironments)
#   - NSG (allows APIM dependencies, denies all internet outbound)
#   - Private DNS zone (azure-api.net) linked to the VNet
#   - APIM Premium v2 (Internal VNet injection)
#   - Private DNS A record mapping gateway hostname to APIM private VIP
#   - Private Endpoint subnet + management-plane Private Endpoint
#   - publicNetworkAccess = Disabled on APIM
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
resource "azurerm_network_security_group" "apim_nsg" {
  name                = "nsg-apim"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

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

      virtualNetworkType = "Internal"
      virtualNetworkConfiguration = {
        subnetResourceId = azurerm_subnet.apim.id
      }
    }
    },
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

# ── Private DNS A Record for the gateway ─────────────────────
resource "azurerm_private_dns_a_record" "apim_gateway" {
  name                = var.apim_name
  zone_name           = azurerm_private_dns_zone.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  ttl                 = 300
  records             = [azapi_resource.apim.output.properties.privateIPAddresses[0]]
}
