# The cluster-access layer: what the cluster and its workloads may do in Azure.
# (Per-workload identities and their Key Vault rights: workload-identity.tf.)
#
# Three layers, three lifetimes:
#   terraform/persistent   never destroyed (Key Vault, registry, static IP, DNS)
#   infra-aks/cluster      destroyed and rebuilt (the cluster itself)
#   terraform/cluster-access (this)  re-applied after every rebuild
#
# A rebuilt cluster has new identities, so the role assignments that point at
# them must be created again. Keeping them here (and not in the shared
# infra-aks repo) keeps Restauranty's rights out of the voting app's cluster
# code. Everything below is read as a data source, so `terraform destroy`
# here removes only role assignments.

data "azurerm_kubernetes_cluster" "aks" {
  name                = var.cluster_name
  resource_group_name = var.cluster_resource_group
}

data "azurerm_resource_group" "persistent" {
  name = var.persistent_resource_group
}

data "azurerm_container_registry" "main" {
  name                = var.acr_name
  resource_group_name = var.persistent_resource_group
}

# The cluster's own (control plane) identity. The module creates it as a
# user-assigned identity; the data source above only gives its resource id.
data "azurerm_user_assigned_identity" "cluster" {
  name                = provider::azurerm::parse_resource_id(one(data.azurerm_kubernetes_cluster.aks.identity[0].identity_ids))["resource_name"]
  resource_group_name = var.cluster_resource_group
}

# ---------------------------------------------------------------------------
# Image pulls: the kubelet (the agent on each node that starts containers)
# signs in to the registry with its own identity. Pull only, no push.
# ---------------------------------------------------------------------------
resource "azurerm_role_assignment" "kubelet_acr_pull" {
  scope                            = data.azurerm_container_registry.main.id
  role_definition_name             = "AcrPull"
  principal_id                     = data.azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  skip_service_principal_aad_check = true
}

# ---------------------------------------------------------------------------
# Static IP: the Gateway's load balancer uses the IP in the persistent
# resource group, not one in the cluster's node resource group. AKS may only
# attach an IP it is allowed to "join", so the cluster identity needs
# Network Contributor on that group. Scope: that one group, not the
# subscription.
# ---------------------------------------------------------------------------
resource "azurerm_role_assignment" "cluster_network_contributor" {
  scope                            = data.azurerm_resource_group.persistent.id
  role_definition_name             = "Network Contributor"
  principal_id                     = data.azurerm_user_assigned_identity.cluster.principal_id
  skip_service_principal_aad_check = true
}
