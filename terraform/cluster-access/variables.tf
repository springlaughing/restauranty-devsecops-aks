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
