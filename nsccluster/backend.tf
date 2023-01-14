terraform {
  backend "s3" {
    bucket         = "pjnpoci_tf_backend"
    key            = "terraform-oci-platform/nonprod"
    region         = "${var.oci_region}"
    endpoint = "https://axgi7clmxnue.compat.objectstorage.us-phoenix-1.oraclecloud.com"
    # shared_credentials_file = "Set this from command line"
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    force_path_style            = true
  }
}