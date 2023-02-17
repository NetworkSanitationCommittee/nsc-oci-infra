
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

module "total_cluster" {
  source = "git::https://github.com/catalystsquad/terraform-oci-infra.git/modules/oke-everything"

  compartment_ocid = var.compartment_ocid
  node_ocpus       = 1
  boot_volume_gbs  = 20
}

module "bootstrap" {
  count      = 1
  depends_on = [module.total_cluster]
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
    "metricsAwsAccessKeyId" : module.total_cluster.metrics_bucket_user_key_id,
    "metricsAwsSecretAccessKey" : module.total_cluster.metrics_bucket_user_access_key,
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
    "ecrAccessKeyId" : local.secrets.ecrAccessKeyId,
    "ecrSecretAccessKey" : local.secrets.ecrSecretAccessKey,
  })
}


