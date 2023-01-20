
variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "user_ocid" {}
variable "fingerprint" {
  sensitive = true
}
variable "private_key_path" {}
variable "oci_region" {}
variable "platform_secret_ocid" {}
variable "dns_zone_name" {}

