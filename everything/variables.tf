
variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "user_ocid" {}
variable "fingerprint" {
  sensitive = true
}
variable "private_key_path" {}
variable "oci_region" {}
variable "platform_secret_ocid" {
  type = string
}
variable "dns_zone_name" {}

variable "infra_set_name" {
  type        = string
  default     = "catalystoci"
  description = "The name we apply to resources. Can be ignored for single-cluster setups."
}

variable "global_freeform_tags" {
  default = {
    "env"           = "everything",
    "creator"       = "Tod Hansmann",
    "creator_email" = "tod@phonejanitor.com",
  }
}
