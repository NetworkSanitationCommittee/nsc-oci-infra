terraform {
  required_version = ">= 1.2.0"

  required_providers {
    oci = {
      source  = "hashicorp/oci"
      version = ">= 4.0.0"
    }
    # kubernetes = {
    #   source  = "hashicorp/kubernetes"
    #   version = "~> 2.0"
    # }
    # tls = {
    #   source  = "hashicorp/tls"
    #   version = "~> 3.0"
    # }
  }
}

locals {
#   kubernetes_provider_command_args = [
#     "eks", "get-token",
#     "--region", local.aws_region,
#     "--cluster-name", module.platform.eks_cluster_id,
#     "--role-arn", local.aws_provider_assume_role_arn,
#   ]



#  global_tags = {
#    "env" = "nonprod"
#  }
}
variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "user_ocid" {}
variable "fingerprint" {
    sensitive=true
}
variable "private_key_path" {}
variable "region" {}

provider "oci" {
   tenancy_ocid = "${var.tenancy_ocid}"
   user_ocid = "${var.user_ocid}"
   fingerprint = "${var.fingerprint}"
   private_key_path = "${var.private_key_path}"
   region = "${var.oci_region}"
}


# provider "kubernetes" {
#   # overwrite config_path to ensure existing kubeconfig does not get used
#   config_path = ""

#   # build kube config based on output of platform module to ensure that it
#   # speaks to the new cluster when creating the aws-auth configmap
#   host                   = module.platform.eks_cluster_endpoint
#   cluster_ca_certificate = base64decode(module.platform.eks_cluster_certificate_authority_data)

#   exec {
#     api_version = "client.authentication.k8s.io/v1beta1"
#     command     = "aws"
#     args        = local.kubernetes_provider_command_args
#   }
# }
