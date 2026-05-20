# Outputs consumed by downstream stages (stage2, stage3).
# CI/CD: capture these from `terraform output -json` and pass to next stage as vars.

output "subscription_id" {
  description = "Subscription where APIM lives."
  value       = var.subscription_id
}

output "resource_group_name" {
  description = "Resource group containing APIM."
  value       = data.azurerm_resource_group.rg.name
}

output "apim_name" {
  description = "APIM instance name."
  value       = var.apim_name
}

output "apim_resource_id" {
  description = "Full ARM resource ID of the APIM instance."
  value       = module.apim.resource_id
}

output "apim_gateway_url" {
  description = "Private gateway URL for the APIM instance."
  value       = "https://${var.apim_name}.azure-api.net"
}

output "apim_private_ip" {
  description = "Private IP address of the APIM gateway (internal load balancer VIP)."
  value       = module.apim.resource.private_ip_addresses[0]
  sensitive   = true
}

output "vnet_id" {
  description = "Resource ID of the VNet."
  value       = data.azurerm_virtual_network.vnet.id
}

output "vnet_name" {
  description = "Name of the VNet (consumed by the App Service script for stage 3)."
  value       = data.azurerm_virtual_network.vnet.name
}

output "apim_subnet_id" {
  description = "Resource ID of the APIM subnet."
  value       = data.azurerm_subnet.apim.id
}

output "private_dns_zone_id" {
  description = "Resource ID of the azure-api.net private DNS zone."
  value       = data.azurerm_private_dns_zone.apim.id
}
