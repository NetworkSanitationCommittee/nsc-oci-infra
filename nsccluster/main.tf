
module "network" {
  source   = "../modules/oke-network"

  compartment_id = ${var.compartment_ocid}
}

module "cluster" {
  source   = "../modules/oke-cluster"

  compartment_id = ${var.compartment_ocid}
  kubernetes_version = "1.24.1"

  global_freeform_tags = {
    "env" = "everything",
    "creator" = "Tod Hansmann",
    "creator_email" = "tod@phonejanitor.com",
  }

  vcn_id = module.network.vcn_id
  nsg_id = module.network.network_security_group_id
  public_subnet_id = module.network.subnet_ids[0]
  loadbalancer_subnet_ids = [module.network.subnet_ids[0]]
  regional_subnet_a_id = module.network.subnet_ids[2]
  nodepool_a_subnet_ids = [module.network.subnet_ids[2]]
  regional_subnet_b_id = module.network.subnet_ids[3]
  nodepool_b_subnet_ids = [module.network.subnet_ids[3]]
}

