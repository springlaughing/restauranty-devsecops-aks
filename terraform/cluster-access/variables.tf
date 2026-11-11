variable "cluster_name" {
  description = "The AKS cluster (from infra-aks/cluster). Read only."
  type        = string
  default     = "aks-evgenia-k8s-dev"
}

variable "cluster_resource_group" {
  description = "Resource group of the AKS cluster."
  type        = string
  default     = "rg-evgenia-k8s-dev"
}

variable "persistent_resource_group" {
  description = "The never-destroyed resource group from terraform/persistent (registry, Key Vault, static IP)."
  type        = string
  default     = "rg-evgenia-restauranty"
}

variable "acr_name" {
  description = "The container registry from terraform/persistent."
  type        = string
  default     = "acrevgeniarestauranty"
}

variable "key_vault_name" {
  description = "The Key Vault from terraform/persistent."
  type        = string
  default     = "kv-evgenia-restauranty"
}

variable "app_namespace" {
  description = "Kubernetes namespace of the app's ServiceAccounts."
  type        = string
  default     = "restauranty"
}

variable "workload_secrets" {
  description = "Which Key Vault secrets each workload may read. One identity per key, named like its ServiceAccount."
  type        = map(list(string))
  default = {
    auth      = ["jwt-private-key", "mongo-password"]
    discounts = ["jwt-public-key", "mongo-password"]
    items     = ["jwt-public-key", "mongo-password", "cloud-name", "cloud-api-key", "cloud-api-secret"]
    mongodb   = ["mongo-root-password", "mongo-password"]
    grafana   = ["grafana-admin-password"] # Grafana's login (#14), in the monitoring namespace
  }
}

variable "workload_namespaces" {
  description = "Namespace of a workload's ServiceAccount, for workloads outside app_namespace."
  type        = map(string)
  default = {
    grafana = "monitoring"
  }
}
