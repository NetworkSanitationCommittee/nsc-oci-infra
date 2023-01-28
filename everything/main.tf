locals {
  # Variables can not reference other variables in their default
  # This allows us to overwrite a compartment_ocid with the tenancy_ocid if the compartment_ocid
  # is not set at all
  resolved_compartment_ocid = "${var.compartment_ocid}" != "" ? "${var.compartment_ocid}" : "${var.tenancy_ocid}"
}

module "network" {
  #source = "git::https://github.com/catalystsquad/terraform-oci-infra.git//modules/oke-network"
  source = "../modules/oke-network"

  compartment_id = local.resolved_compartment_ocid
}

module "cluster" {
  #source = "git::https://github.com/catalystsquad/terraform-oci-infra.git//modules/oke-cluster"
  source = "../modules/oke-cluster"

  compartment_id     = local.resolved_compartment_ocid
  kubernetes_version = "1.25.4"

  global_freeform_tags    = var.global_freeform_tags
  vcn_id                  = module.network.vcn_id
  nsg_id                  = module.network.network_security_group_id
  public_subnet_id        = module.network.public_regional_subnet_id
  loadbalancer_subnet_ids = [module.network.public_subnet_a_id, module.network.public_subnet_b_id]
  service_subnet_cidr     = "10.21.0.0/16"

  #regional_subnet_a_id  = module.network.private_subnet_ids[0]
  #nodepool_a_subnet_ids = [module.network.private_subnet_ids[0]]
  #regional_subnet_b_id  = module.network.private_subnet_ids[1]
  #nodepool_b_subnet_ids = [module.network.private_subnet_ids[1]]
  #public_subnet_a_id    = module.network.public_subnet_a
  nodepool_a_subnet_ids = [module.network.private_subnet_a_id]
  #public_subnet_b_id    = module.network.public_subnet_b
  nodepool_b_subnet_ids = [module.network.private_subnet_b_id]
}

resource "oci_objectstorage_bucket" "platform_metrics_bucket" {
  compartment_id = local.resolved_compartment_ocid
  name           = "${var.infra_set_name}_catalyst_metrics_bucket"
  namespace      = "axgi7clmxnue"
}

resource "oci_identity_user" "platform_metrics_bucket_user" {
  compartment_id = local.resolved_compartment_ocid
  name           = "${var.infra_set_name}_catalyst_metrics_bucket_user"
  email          = "tod+${var.infra_set_name}@phonejanitor.com"
  description    = "User to access the ${var.infra_set_name}_catalyst_metrics_bucket_user"
  freeform_tags  = merge(var.global_freeform_tags, {})
}

resource "oci_identity_group" "platform_metrics_users" {
  compartment_id = local.resolved_compartment_ocid
  description    = "Group for managing access to ${var.infra_set_name}_catalyst_metrics_bucket"
  name           = "${var.infra_set_name}_metrics_users"

  freeform_tags = merge(var.global_freeform_tags, {})
}

resource "oci_identity_policy" "platform_metrics_bucket_user_policy" {
  compartment_id = local.resolved_compartment_ocid
  description    = "Allow the metrics bucket user have access to the metrics bucket of th ${var.infra_set_name} stack."
  name           = "${var.infra_set_name}_catalyst_metrics_bucket_user_policy"
  statements = [
    "Allow group ${var.infra_set_name}_metrics_users to manage buckets in tenancy where all {target.bucket.name='{var.infra_set_name}_catalyst_metrics_bucket'}",
    "Allow group ${var.infra_set_name}_metrics_users to manage objects in tenancy where all {target.bucket.name='{var.infra_set_name}_catalyst_metrics_bucket'}",
  ]

  freeform_tags = merge(var.global_freeform_tags, {})
}

resource "oci_identity_user_group_membership" "platform_metrics_bucket_users_group_membership" {
  group_id = oci_identity_group.platform_metrics_users.id
  user_id  = oci_identity_user.platform_metrics_bucket_user.id
}

resource "oci_identity_customer_secret_key" "platform_metrics_bucket_user_key" {
  display_name = "Keys for the ${var.infra_set_name}_catalyst_metrics_bucket_user"
  user_id      = oci_identity_user.platform_metrics_bucket_user.id
}

locals {
  metrics_bucket_namespaces = [
    "cortex",
    "loki",
  ]
}

# manage secrets for this environment via oci secrets manager for secret
# versioning and oci access control over secrets
data "oci_secrets_secretbundle" "platform_secrets" {
  secret_id = var.platform_secret_ocid
}

locals {
  environment_name = "everything"
  secrets = sensitive(
    jsondecode(
      base64decode(
        data.oci_secrets_secretbundle.platform_secrets.secret_bundle_content.0.content
      )
    )
  )
}

resource "kubernetes_storage_class" "platform_storage_class_paravirtualized" {
  metadata {
    name = "oci-bv-enc"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }
  storage_provisioner = "blockvolume.csi.oraclecloud.com"
  reclaim_policy      = "Retain"
  parameters = {
    attachment-type = "paravirtualized"
  }
  allow_volume_expansion = true
  volume_binding_mode    = "WaitForFirstConsumer"
}

module "bootstrap" {
  count      = 1
  depends_on = [module.cluster, kubernetes_storage_class.platform_storage_class_paravirtualized]
  source     = "catalystsquad/catalyst-cluster-bootstrap/kubernetes"
  version    = "~> 1.0"

  enable_platform_services          = true
  cert_manager_cloudflare_api_token = local.secrets.cloudflareApiToken
  argo_cd_chart_version             = "4.9.12"

  kube_prometheus_stack_values = [
    templatefile("./helm-values/prometheus.yaml", {
      "clusterName" : local.environment_name,
    })
  ]

  argo_cd_values = [
    templatefile("./helm-values/argocd.yaml", {
      "helmRepoPat" : local.secrets.helmRepoPat,
    })
  ]


  platform_services_values = templatefile("./helm-values/${local.environment_name}-platform-services.yaml", {
    "metricsBucketName" : "${var.infra_set_name}_catalyst_metrics_bucket"
    "metricsAwsAccessKeyId" : oci_identity_customer_secret_key.platform_metrics_bucket_user_key.id,
    "metricsAwsSecretAccessKey" : oci_identity_customer_secret_key.platform_metrics_bucket_user_key.key,
    "cloudflareApiToken" : local.secrets.cloudflareApiToken,
    "grafanaDatasourceCortexPassword" : local.secrets.grafanaDatasourceCortexPassword,
    "grafanaDatasourceLokiPassword" : local.secrets.grafanaDatasourceLokiPassword,
    "grafanaAdminPassword" : local.secrets.grafanaAdminPassword,
    "grafanaNotifierProductEngineeringTeams" : local.secrets.grafanaNotifierProductEngineeringTeams,
    "grafanaNotifierCatalystSquadSlack" : local.secrets.grafanaNotifierCatalystSquadSlack,
    "promtailBasicAuthPassword" : local.secrets.promtailBasicAuthPassword,
    "sentryPostgresqlPassword" : local.secrets.sentryPostgresqlPassword,
    "sentryUserPassword" : local.secrets.sentryUserPassword,
    "sentryRedisAuthPassword" : local.secrets.sentryRedisAuthPassword,
    "sentrySystemSecretKey" : local.secrets.sentrySystemSecretKey,
    # issuer key pem is stored as base64 becase it is a multiline string.
    # decode base64 then use the indent function to ensure it is properly
    # formatted in yaml
    "linkerdIssuerKeyPEM" : indent(12, base64decode(local.secrets.linkerdIssuerKeyPEMb64)),
  })
}

resource "kubernetes_secret_v1" "prometheus_remote_write" {
  for_each = toset(local.metrics_bucket_namespaces)

  metadata {
    name      = "metricsbucketaccess"
    namespace = each.key
  }

  data = {
    #AWS_ACCESS_KEY_ID
    access_key_id = oci_identity_customer_secret_key.platform_metrics_bucket_user_key.id
    #AWS_SECRET_ACCESS_KEY 
    secret_access_key = oci_identity_customer_secret_key.platform_metrics_bucket_user_key.key
  }

  depends_on = [
    module.cluster,
    module.bootstrap,
  ]
}

