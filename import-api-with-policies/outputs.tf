output "petstore_api_id" {
  description = "ARM resource ID of the imported Petstore API."
  value       = azapi_resource.petstore_api.id
}

output "petstore_api_url" {
  description = "Base URL for the Petstore API through APIM."
  value       = "https://${var.apim_name}.azure-api.net/${var.petstore_api_path}"
}
