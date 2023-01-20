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
  kubernetes_version = "1.25.4"

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

resource "oci_objectstorage_bucket" "metrics-bucket" {
  compartment_id = local.resolved_compartment_ocid
  name           = "nsc-metrics-bucket"
  namespace      = "nsc"
}

locals {
  environment_name = "everything"
}

# manage secrets for this environment via aws secrets manager for secret
# versioning and aws access control over secrets
data "oci_secrets_secretbundle" "platform_secrets" {
  secret_id = var.platform_secret_ocid
}

locals {
  secrets = jsondecode(
    base64decode(
      data.oci_secrets_secretbundle.platform_secrets.secret_bundle_content.0.content
    )
  )
}

module "bootstrap" {
  source  = "catalystsquad/catalyst-cluster-bootstrap/kubernetes"
  version = "~> 1.0"

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
