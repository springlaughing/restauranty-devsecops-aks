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
