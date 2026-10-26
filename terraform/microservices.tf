# Import the resources bootstrapped by the operator before the first apply.
# No database passwords or storage credentials are managed in Terraform state.
variable "microservices_enabled" {
  type    = bool
  default = false
}
variable "microservice_images" {
  type    = map(string)
  default = {}
}
variable "microservice_urls" {
  type    = map(string)
  default = {}
}
variable "neon_auth_environment" {
  type    = map(string)
  default = {}
}
variable "document_storage_environment" {
  type    = map(string)
  default = {}
}
variable "service_database_secret_versions" {
  description = "Reviewed numeric versions of existing pooled/direct DB secrets; set during coordinated database cutover. Secret values never enter Terraform."
  type = map(object({
    pooled = string
    direct = string
  }))
  default = {}
  validation {
    condition = alltrue([for service, versions in var.service_database_secret_versions :
      contains(["identity", "rental", "documents", "notifications", "metering", "billing"], service) &&
      can(regex("^[1-9][0-9]*$", versions.pooled)) && can(regex("^[1-9][0-9]*$", versions.direct))
    ])
    error_message = "Only the six data-owning services and explicit positive numeric secret versions are permitted."
  }
}
locals {
  micro_accounts = var.microservices_enabled ? setunion(toset(["gateway", "identity", "rental", "documents", "notifications", "pubsub-push", "outbox-scheduler"]), local.accounting_services) : toset([])
  micro_services = var.microservices_enabled ? setunion(toset(["identity", "rental", "documents", "notifications"]), local.accounting_services) : toset([])
  micro_secrets = { for key in local.micro_services : key => merge({
    DATABASE_URL          = { secret = "psi-${key}-database-url", version = try(var.service_database_secret_versions[key].pooled, "1") }
    DATABASE_URL_UNPOOLED = { secret = "psi-${key}-database-url-unpooled", version = try(var.service_database_secret_versions[key].direct, "1") }
    }, key == "documents" ? {
    AWS_ACCESS_KEY_ID     = { secret = "psi-be-neon-aws-access-key-id", version = "1" }
    AWS_SECRET_ACCESS_KEY = { secret = "psi-be-neon-aws-secret-access-key", version = "1" }
  } : {}) }
  micro_secret_grants = merge({}, [for service, secrets in local.micro_secrets : {
    for env, ref in secrets : "${service}-${env}" => { service = service, secret = ref.secret }
  }]...)
  invocation_edges = merge(var.microservices_enabled ? {
    "identity-gateway"       = ["identity", "gateway"]
    "identity-rental"        = ["identity", "rental"]
    "identity-documents"     = ["identity", "documents"]
    "identity-notifications" = ["identity", "notifications"]
    "rental-gateway"         = ["rental", "gateway"]
    "rental-documents"       = ["rental", "documents"]
    "rental-scheduler"       = ["rental", "outbox-scheduler"]
    "documents-gateway"      = ["documents", "gateway"]
    "notifications-gateway"  = ["notifications", "gateway"]
    "notifications-pubsub"   = ["notifications", "pubsub-push"]
    } : {}, var.accounting_enabled ? {
    "identity-metering"  = ["identity", "metering"]
    "identity-billing"   = ["identity", "billing"]
    "rental-metering"    = ["rental", "metering"]
    "rental-billing"     = ["rental", "billing"]
    "metering-gateway"   = ["metering", "gateway"]
    "billing-gateway"    = ["billing", "gateway"]
    "metering-pubsub"    = ["metering", "pubsub-push"]
    "billing-pubsub"     = ["billing", "pubsub-push"]
    "metering-scheduler" = ["metering", "outbox-scheduler"]
    "billing-scheduler"  = ["billing", "outbox-scheduler"]
  } : {})
}
data "google_project" "micro" {
  count      = var.microservices_enabled ? 1 : 0
  project_id = var.project_id
}
resource "google_project_service" "micro" {
  for_each           = var.microservices_enabled ? toset(["pubsub.googleapis.com", "cloudscheduler.googleapis.com"]) : toset([])
  project            = var.project_id
  service            = each.key
  disable_on_destroy = false
}
resource "google_service_account" "micro" {
  for_each     = local.micro_accounts
  project      = var.project_id
  account_id   = "psi-${each.key}"
  display_name = "psi-${each.key}"
}
resource "google_secret_manager_secret_iam_member" "micro" {
  for_each  = local.micro_secret_grants
  project   = var.project_id
  secret_id = each.value.secret
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.micro[each.value.service].email}"
}
module "microservices" {
  for_each                = local.micro_services
  source                  = "./modules/cloud-run"
  project_id              = var.project_id
  region                  = var.region
  service_name            = "psi-${each.key}"
  container_image         = var.microservice_images[each.key]
  container_port          = 8080
  min_instance_count      = 0
  max_instance_count      = 1
  allow_unauthenticated   = false
  runtime_service_account = google_service_account.micro[each.key].email
  container_memory        = "512Mi"
  startup_cpu_boost       = true
  labels                  = local.labels
  runtime_secrets         = local.micro_secrets[each.key]
  runtime_environment = merge(var.neon_auth_environment, {
    SERVICE_SCHEMA = each.key
    DB_POOL_SIZE   = "3"
    NEON_BRANCH    = "production"
    }, each.key == "identity" ? {} : { IDENTITY_SERVICE_URL = var.microservice_urls["identity"] },
    each.key == "documents" ? merge(var.document_storage_environment, { RENTAL_SERVICE_URL = var.microservice_urls["rental"] }) : {},
    each.key == "rental" ? {
      PUBSUB_PROJECT         = var.project_id
      PUBSUB_TOPIC           = "rental-events-v1"
      INTERNAL_AUTH_MODE     = "google"
      INTERNAL_AUDIENCE      = var.microservice_urls["rental"]
      INTERNAL_CALLER_EMAILS = google_service_account.micro["outbox-scheduler"].email
      } : {}, each.key == "notifications" ? {
      PUBSUB_SUBSCRIPTION    = "projects/${var.project_id}/subscriptions/rental-notifications-v1"
      INTERNAL_AUTH_MODE     = "google"
      INTERNAL_AUDIENCE      = var.microservice_urls["notifications"]
      INTERNAL_CALLER_EMAILS = google_service_account.micro["pubsub-push"].email
      } : {}, contains(local.accounting_services, each.key) ? {
      RENTAL_SERVICE_URL     = var.microservice_urls["rental"]
      PUBSUB_PROJECT         = var.project_id
      PUBSUB_TOPIC           = "${each.key}-events-v1"
      PUBSUB_SUBSCRIPTIONS   = each.key == "metering" ? "projects/${var.project_id}/subscriptions/rental-metering-v1" : "projects/${var.project_id}/subscriptions/rental-billing-v1,projects/${var.project_id}/subscriptions/metering-billing-v1"
      INTERNAL_AUTH_MODE     = "google"
      INTERNAL_AUDIENCE      = var.microservice_urls[each.key]
      INTERNAL_CALLER_EMAILS = "${google_service_account.micro["pubsub-push"].email},${google_service_account.micro["outbox-scheduler"].email}"
      } : {}, each.key == "notifications" && var.accounting_enabled ? {
      PUBSUB_SUBSCRIPTIONS = "projects/${var.project_id}/subscriptions/rental-notifications-v1,projects/${var.project_id}/subscriptions/metering-notifications-v1,projects/${var.project_id}/subscriptions/billing-notifications-v1"
  } : {})
  depends_on = [google_secret_manager_secret_iam_member.micro]
}
resource "google_cloud_run_v2_service_iam_member" "micro" {
  for_each   = local.invocation_edges
  project    = var.project_id
  location   = var.region
  name       = "psi-${each.value[0]}"
  role       = "roles/run.invoker"
  member     = "serviceAccount:${google_service_account.micro[each.value[1]].email}"
  depends_on = [module.microservices]
}
resource "google_pubsub_topic" "rental_events" {
  count                      = var.microservices_enabled ? 1 : 0
  project                    = var.project_id
  name                       = "rental-events-v1"
  message_retention_duration = "86400s"
  depends_on                 = [google_project_service.micro]
}
resource "google_pubsub_topic" "dead_letter" {
  count                      = var.microservices_enabled ? 1 : 0
  project                    = var.project_id
  name                       = "rental-events-dead-letter-v1"
  message_retention_duration = "86400s"
  depends_on                 = [google_project_service.micro]
}
resource "google_pubsub_topic_iam_member" "rental_publisher" {
  count   = var.microservices_enabled ? 1 : 0
  project = var.project_id
  topic   = google_pubsub_topic.rental_events[0].name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.micro["rental"].email}"
}
resource "google_pubsub_topic_iam_member" "dead_letter_publisher" {
  count   = var.microservices_enabled ? 1 : 0
  project = var.project_id
  topic   = google_pubsub_topic.dead_letter[0].name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:service-${data.google_project.micro[0].number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}
resource "google_service_account_iam_member" "pubsub_token_creator" {
  count              = var.microservices_enabled ? 1 : 0
  service_account_id = google_service_account.micro["pubsub-push"].name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${data.google_project.micro[0].number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}
resource "google_pubsub_subscription" "notifications" {
  count                      = var.microservices_enabled ? 1 : 0
  project                    = var.project_id
  name                       = "rental-notifications-v1"
  topic                      = google_pubsub_topic.rental_events[0].id
  ack_deadline_seconds       = 30
  message_retention_duration = "86400s"
  retry_policy {
    minimum_backoff = "5s"
    maximum_backoff = "60s"
  }
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter[0].id
    max_delivery_attempts = 10
  }
  push_config {
    push_endpoint = "${var.microservice_urls["notifications"]}/internal/events"
    oidc_token {
      service_account_email = google_service_account.micro["pubsub-push"].email
      audience              = var.microservice_urls["notifications"]
    }
  }
  expiration_policy { ttl = "" }
  depends_on = [google_cloud_run_v2_service_iam_member.micro, google_service_account_iam_member.pubsub_token_creator]
}
resource "google_pubsub_subscription_iam_member" "dead_letter_subscriber" {
  count        = var.microservices_enabled ? 1 : 0
  subscription = google_pubsub_subscription.notifications[0].id
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:service-${data.google_project.micro[0].number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}
resource "google_pubsub_subscription" "dead_letter" {
  count                      = var.microservices_enabled ? 1 : 0
  project                    = var.project_id
  name                       = "rental-dead-letter-monitor-v1"
  topic                      = google_pubsub_topic.dead_letter[0].id
  message_retention_duration = "604800s"
  expiration_policy { ttl = "" }
}
resource "google_cloud_scheduler_job" "outbox" {
  count            = var.microservices_enabled ? 1 : 0
  project          = var.project_id
  region           = var.region
  name             = "rental-outbox-dispatch"
  schedule         = "* * * * *"
  time_zone        = "UTC"
  attempt_deadline = "120s"
  retry_config { retry_count = 3 }
  http_target {
    uri         = "${var.microservice_urls["rental"]}/internal/outbox/dispatch"
    http_method = "POST"
    oidc_token {
      service_account_email = google_service_account.micro["outbox-scheduler"].email
      audience              = var.microservice_urls["rental"]
    }
  }
  depends_on = [google_project_service.micro, google_cloud_run_v2_service_iam_member.micro]
}
