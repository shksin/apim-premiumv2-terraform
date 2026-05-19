output "api_id" {
  description = "ARM resource ID of the imported API."
  value       = azapi_resource.api.id
}

output "api_url" {
  description = "Base URL for the API through APIM."
  value       = "https://${var.apim_name}.azure-api.net/${var.api_path}"
}
