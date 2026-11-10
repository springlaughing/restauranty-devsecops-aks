variable "student_name" {
  description = "Owner prefix for resource names and the Owner tag."
  type        = string
  default     = "evgenia"
}

variable "project" {
  description = "Short project name, used in resource names and tags."
  type        = string
  default     = "restauranty"
}

variable "location" {
  description = "Azure region. Same as the cluster, so traffic stays in one region."
  type        = string
  default     = "germanywestcentral"
}

variable "acr_name" {
  description = "Container registry name: globally unique, 5-50 letters and digits only. Change it if the default is taken."
  type        = string
  default     = "acrevgeniarestauranty"

  validation {
    condition     = can(regex("^[a-zA-Z0-9]{5,50}$", var.acr_name))
    error_message = "acr_name must be 5-50 letters and digits, no hyphens."
  }
}

variable "dns_zone_name" {
  description = "Existing DNS zone (from infra-aks/dns). Read only, never managed here."
  type        = string
  default     = "aks.springlaughing.dev"
}

variable "dns_zone_resource_group" {
  description = "Resource group of the existing DNS zone."
  type        = string
  default     = "rg-evgenia-dns"
}

variable "dns_hostnames" {
  description = "Names in the zone that point at the Gateway's static IP."
  type        = list(string)
  default     = ["restauranty", "grafana"]
}

# GitHub puts the numeric ids of the owner and the repo into the subject
# ("immutable subject"). With names only, someone who later took over the name
# springlaughing could create a repo with the same name, and Azure would trust
# their jobs. The ids never move to another account.
# Check it with: gh api repos/springlaughing/restauranty-devsecops-aks/actions/oidc/customization/sub
variable "github_subject_prefix" {
  description = "Start of the OIDC subject GitHub sends for this repo: repo:<owner>@<owner id>/<repo>@<repo id>."
  type        = string
  default     = "repo:springlaughing@31309521/restauranty-devsecops-aks@1450795318"
}
