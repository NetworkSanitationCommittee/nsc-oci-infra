locals {
  # Variables can not reference other variables in their default
  # This allows us to overwrite a compartment_ocid with the tenancy_ocid if the compartment_ocid
  # is not set at all
  resolved_compartment_ocid = "${var.compartment_ocid}" != "" ? "${var.compartment_ocid}" : "${var.tenancy_ocid}"
}

module "network" {
  source = "git::https://github.com/catalystsquad/terraform-oci-infra.git//modules/oke-network"

  compartment_id = local.resolved_compartment_ocid
}

module "cluster" {
  source = "git::https://github.com/catalystsquad/terraform-oci-infra.git//modules/oke-cluster"

  compartment_id     = local.resolved_compartment_ocid
  kubernetes_version = "1.24.1"

  global_freeform_tags = {
    "env"           = "everything",
    "creator"       = "Tod Hansmann",
    "creator_email" = "tod@phonejanitor.com",
  }

  vcn_id                  = module.network.vcn_id
  nsg_id                  = module.network.network_security_group_id
  public_subnet_id        = module.network.subnet_ids[0]
  loadbalancer_subnet_ids = [module.network.subnet_ids[0]]
  regional_subnet_a_id    = module.network.subnet_ids[2]
  nodepool_a_subnet_ids   = [module.network.subnet_ids[2]]
  regional_subnet_b_id    = module.network.subnet_ids[3]
  nodepool_b_subnet_ids   = [module.network.subnet_ids[3]]
}

