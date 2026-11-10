# ---------------------------------------------------------------------------
# GitHub Actions signs in to Azure with OIDC: no password or key is stored in
# GitHub. For each job, GitHub issues a short-lived token that says which repo,
# branch or environment the job runs for (the "subject"). Entra ID trades it
# for an Azure token only if a federated credential below trusts exactly that
# subject. A job from any other branch, fork or repo is refused.
#
# Two identities, so the powerful one is used only after a human approves:
#
#   pipeline  (main.tf)  push images to the registry   trusted for: branch main
#   deploy    (here)     deploy to the AKS cluster     trusted for: environment
#                                                      "production", which
#                                                      waits for my approval
#
# A build job that runs a poisoned npm package can push an image, but it
# cannot touch the cluster: it never gets the deploy identity.
# ---------------------------------------------------------------------------

locals {
  github_issuer   = "https://token.actions.githubusercontent.com"
  github_audience = ["api://AzureADTokenExchange"]
}

# Build and push: every merge to main, no approval needed.
resource "azurerm_federated_identity_credential" "pipeline_main" {
  name                      = "github-main"
  user_assigned_identity_id = azurerm_user_assigned_identity.pipeline.id
  issuer                    = local.github_issuer
  audience                  = local.github_audience
  subject                   = "repo:${var.github_repo}:ref:refs/heads/main"
}

# Deploy: a separate identity. Its only right is on the cluster
# (terraform/cluster-access/pipeline.tf).
resource "azurerm_user_assigned_identity" "deploy" {
  name                = "id-${local.name_suffix}-deploy"
  resource_group_name = azurerm_resource_group.persistent.name
  location            = azurerm_resource_group.persistent.location
  tags                = local.common_tags
}

# Trusted only for jobs in the GitHub environment "production". That
# environment has a required reviewer (me), so the job waits for approval
# before GitHub even issues its token.
resource "azurerm_federated_identity_credential" "deploy_production" {
  name                      = "github-production"
  user_assigned_identity_id = azurerm_user_assigned_identity.deploy.id
  issuer                    = local.github_issuer
  audience                  = local.github_audience
  subject                   = "repo:${var.github_repo}:environment:production"
}
