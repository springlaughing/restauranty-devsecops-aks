# ---------------------------------------------------------------------------
# One Azure identity per workload, each allowed to read only its own secrets.
#
# How a workload proves who it is, with no password anywhere:
#   1. Kubernetes gives the workload's ServiceAccount a short-lived token,
#      signed by the cluster's OIDC issuer.
#   2. Entra ID accepts that token in exchange for an Azure token, because
#      the identity's federated credential says: "trust tokens from THIS
#      issuer for THIS ServiceAccount" (and nothing else).
#   3. With the Azure token, Key Vault hands out only the secrets the
#      identity has a role on.
# External Secrets does steps 1-3 for each workload and writes the result
# into that workload's Kubernetes Secret.
#
# The identities live in the persistent resource group, so their client ids
# stay the same across cluster rebuilds (they are written into the
# ServiceAccounts). A rebuilt cluster has a new OIDC issuer, so only the
# federated credentials are replaced on the next apply.
# ---------------------------------------------------------------------------

data "azurerm_key_vault" "main" {
  name                = var.key_vault_name
  resource_group_name = var.persistent_resource_group
}

resource "azurerm_user_assigned_identity" "workload" {
  for_each = var.workload_secrets

  name                = "id-evgenia-restauranty-${each.key}"
  resource_group_name = data.azurerm_resource_group.persistent.name
  location            = data.azurerm_resource_group.persistent.location
  tags = {
    Owner     = "evgenia"
    Project   = "restauranty"
    Layer     = "cluster-access"
    ManagedBy = "terraform"
  }
}

# "Trust the cluster's token for system:serviceaccount:<namespace>:<name>."
# The namespace is restauranty, except for the workloads listed in
# workload_namespaces (grafana: monitoring).
# Any other ServiceAccount, namespace or cluster is refused by Entra ID.
resource "azurerm_federated_identity_credential" "workload" {
  for_each = var.workload_secrets

  name                      = "aks-${lookup(var.workload_namespaces, each.key, var.app_namespace)}-${each.key}"
  user_assigned_identity_id = azurerm_user_assigned_identity.workload[each.key].id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = data.azurerm_kubernetes_cluster.aks.oidc_issuer_url
  subject                   = "system:serviceaccount:${lookup(var.workload_namespaces, each.key, var.app_namespace)}:${each.key}"
}

# Read access to single secrets, never the whole vault. "Key Vault Secrets
# User" can read a secret's value, not list, change or delete secrets.
# The scope is built as a string: the azurerm_key_vault_secret data source
# would copy each secret VALUE into Terraform state.
locals {
  secret_grants = merge([
    for workload, secrets in var.workload_secrets : {
      for secret in secrets : "${workload}/${secret}" => {
        workload = workload
        secret   = secret
      }
    }
  ]...)
}

resource "azurerm_role_assignment" "secret_read" {
  for_each = local.secret_grants

  scope                            = "${data.azurerm_key_vault.main.id}/secrets/${each.value.secret}"
  role_definition_name             = "Key Vault Secrets User"
  principal_id                     = azurerm_user_assigned_identity.workload[each.value.workload].principal_id
  skip_service_principal_aad_check = true
}
