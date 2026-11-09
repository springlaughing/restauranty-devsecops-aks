output "kubelet_object_id" {
  description = "Object id of the kubelet identity that has AcrPull."
  value       = data.azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
}

output "oidc_issuer_url" {
  description = "The cluster's OIDC issuer, used by the per-service federated credentials (#8)."
  value       = data.azurerm_kubernetes_cluster.aks.oidc_issuer_url
}

output "workload_client_ids" {
  description = "Client id per workload identity, for the azure.workload.identity/client-id annotation on each ServiceAccount."
  value       = { for k, v in azurerm_user_assigned_identity.workload : k => v.client_id }
}

output "tenant_id" {
  description = "Entra ID tenant, for the External Secrets SecretStores."
  value       = data.azurerm_key_vault.main.tenant_id
}
