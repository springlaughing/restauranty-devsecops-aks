# The persistent layer: the things that must survive a daily cluster rebuild.
# The cluster (in the infra-aks repo) is destroyed and recreated; these are not.
# Nothing here depends on the cluster, so `terraform destroy` on the cluster
# never touches a secret, an image or the domain's IP address.

locals {
  # rg-evgenia-restauranty, kv-evgenia-restauranty, pip-evgenia-restauranty ...
  name_suffix = "${var.student_name}-${var.project}"

  common_tags = {
    Owner       = var.student_name
    Project     = var.project
    Layer       = "persistent"
    ManagedBy   = "terraform"
    NeverDelete = "true"
  }
}

# Who is running Terraform: used for the tenant id and to give the operator
# permission to set secret values by hand.
data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "persistent" {
  name     = "rg-${local.name_suffix}"
  location = var.location
  tags     = local.common_tags
}

# ---------------------------------------------------------------------------
# Key Vault: holds the JWT keys, the MongoDB password and the Cloudinary keys.
# RBAC, not access policies, so permissions are Azure role assignments.
# Secret VALUES are set once by hand with `az keyvault secret set`, so they
# never end up in Terraform state.
# ---------------------------------------------------------------------------
resource "azurerm_key_vault" "main" {
  name                = "kv-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.persistent.name
  location            = azurerm_resource_group.persistent.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  tags                = local.common_tags

  # Permissions are role assignments (below), not per-vault access policies.
  rbac_authorization_enabled = true

  # A deleted vault (and its secrets) can be recovered for this many days.
  # Purge protection stays off so the vault can still be fully removed when
  # the course ends; turning it on is a one-way door.
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
}

# The operator (whoever runs Terraform) may read and write secret values, so
# the `az keyvault secret set` step works. Services get read-only roles on
# single secrets later, in the cluster-access layer (#8).
resource "azurerm_role_assignment" "operator_secrets" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ---------------------------------------------------------------------------
# Container registry: holds the service images. Basic tier. Admin user off,
# so the only way in is an Azure identity (the pipeline pushes, the cluster
# pulls).
# ---------------------------------------------------------------------------
resource "azurerm_container_registry" "main" {
  name                = var.acr_name
  resource_group_name = azurerm_resource_group.persistent.name
  location            = azurerm_resource_group.persistent.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = local.common_tags
}

# ---------------------------------------------------------------------------
# Static public IP: the single address the domain points at. It stays the same
# across cluster rebuilds, so the DNS records and the HTTPS certificate never
# chase a new IP. The cluster's load balancer is told to use it (cluster layer).
# ---------------------------------------------------------------------------
resource "azurerm_public_ip" "ingress" {
  name                = "pip-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.persistent.name
  location            = azurerm_resource_group.persistent.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = local.common_tags
}

# ---------------------------------------------------------------------------
# Pipeline identity: GitHub Actions signs in as this, with OIDC and no stored
# password. The federated credential that ties it to the repo is added later,
# once the exact subject is known (#12). Here it gets the right to push images.
# ---------------------------------------------------------------------------
resource "azurerm_user_assigned_identity" "pipeline" {
  name                = "id-${local.name_suffix}-pipeline"
  resource_group_name = azurerm_resource_group.persistent.name
  location            = azurerm_resource_group.persistent.location
  tags                = local.common_tags
}

# The pipeline may push and pull images, nothing more.
resource "azurerm_role_assignment" "pipeline_acr_push" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPush"
  principal_id         = azurerm_user_assigned_identity.pipeline.principal_id
}
