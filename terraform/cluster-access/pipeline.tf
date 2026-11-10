# ---------------------------------------------------------------------------
# The deploy identity (terraform/persistent/github.tf) may fetch credentials
# for this one cluster, and nothing else in Azure.
#
# Known gap: this cluster has no Entra ID integration, so the credentials it
# fetches are full admin inside the cluster. Kubernetes cannot narrow them to
# one namespace without Entra ID and Azure RBAC on the cluster. Two things
# keep the risk small: the identity is used only after my approval (GitHub
# environment "production"), and no other job can get it. Production would
# turn on Entra ID with Azure RBAC and give the pipeline "RBAC Writer" on the
# restauranty namespace only, or use GitOps (Argo CD), where the pipeline
# needs no cluster rights at all.
#
# Lives here, not in persistent: the cluster gets a new id on every rebuild.
# ---------------------------------------------------------------------------

data "azurerm_user_assigned_identity" "deploy" {
  name                = "id-evgenia-restauranty-deploy"
  resource_group_name = data.azurerm_resource_group.persistent.name
}

# Allows "az aks get-credentials" for this cluster only.
resource "azurerm_role_assignment" "deploy_cluster_user" {
  scope                            = data.azurerm_kubernetes_cluster.aks.id
  role_definition_name             = "Azure Kubernetes Service Cluster User Role"
  principal_id                     = data.azurerm_user_assigned_identity.deploy.principal_id
  skip_service_principal_aad_check = true
}
