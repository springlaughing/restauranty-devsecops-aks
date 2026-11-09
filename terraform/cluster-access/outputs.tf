output "kubelet_object_id" {
  description = "Object id of the kubelet identity that has AcrPull."
  value       = data.azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
}

output "oidc_issuer_url" {
  description = "The cluster's OIDC issuer, used by the per-service federated credentials (#8)."
  value       = data.azurerm_kubernetes_cluster.aks.oidc_issuer_url
}
