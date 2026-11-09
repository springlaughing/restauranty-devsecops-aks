output "resource_group_name" {
  description = "The persistent resource group."
  value       = azurerm_resource_group.persistent.name
}

output "key_vault_name" {
  description = "Key Vault name, used with `az keyvault secret set` and by the cluster-access layer."
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "Key Vault URI, used by External Secrets."
  value       = azurerm_key_vault.main.vault_uri
}

output "acr_login_server" {
  description = "Registry address for image names, e.g. <server>/auth:<sha>."
  value       = azurerm_container_registry.main.login_server
}

output "acr_name" {
  description = "Registry name, used with `az acr login`."
  value       = azurerm_container_registry.main.name
}

output "ingress_public_ip" {
  description = "The static IP the DNS A records point at."
  value       = azurerm_public_ip.ingress.ip_address
}

output "ingress_public_ip_resource_group" {
  description = "Resource group of the IP, for the load balancer annotation on the cluster."
  value       = azurerm_resource_group.persistent.name
}

output "pipeline_identity_client_id" {
  description = "Client id of the pipeline identity, for the GitHub Actions azure/login step."
  value       = azurerm_user_assigned_identity.pipeline.client_id
}

output "pipeline_identity_principal_id" {
  description = "Principal (object) id of the pipeline identity, for role assignments."
  value       = azurerm_user_assigned_identity.pipeline.principal_id
}
