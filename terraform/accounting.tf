# Optional independent metering and accounting bounded contexts.
variable "accounting_enabled" {
  type    = bool
  default = false
  validation {
    condition     = !var.accounting_enabled || (var.microservices_enabled && var.independent_delivery_enabled)
    error_message = "Accounting requires private microservices and independent delivery."
  }
}
locals {
  accounting_services = var.accounting_enabled ? toset(["metering", "billing"]) : toset([])
  accounting_subscriptions = var.accounting_enabled ? {
    rental-metering-v1        = { topic = "rental", target = "metering", filter = "attributes.type = \"ContractAccountingChanged\"" }
    rental-billing-v1         = { topic = "rental", target = "billing", filter = "attributes.type = \"ContractAccountingChanged\"" }
    metering-billing-v1       = { topic = "metering", target = "billing", filter = "attributes.type = \"MeterReadingAccepted\"" }
    metering-notifications-v1 = { topic = "metering", target = "notifications", filter = null }
    billing-notifications-v1  = { topic = "billing", target = "notifications", filter = null }
  } : {}
}
resource "google_pubsub_topic" "accounting" {
  for_each                   = local.accounting_services
  project                    = var.project_id
  name                       = "${each.key}-events-v1"
  message_retention_duration = "86400s"
  depends_on                 = [google_project_service.micro]
}
resource "google_pubsub_topic_iam_member" "accounting_publish" {
  for_each = local.accounting_services
  project  = var.project_id
  topic    = google_pubsub_topic.accounting[each.key].name
  role     = "roles/pubsub.publisher"
  member   = "serviceAccount:${google_service_account.micro[each.key].email}"
}
resource "google_pubsub_subscription" "accounting" {
  for_each                   = local.accounting_subscriptions
  project                    = var.project_id
  name                       = each.key
  topic                      = each.value.topic == "rental" ? google_pubsub_topic.rental_events[0].id : google_pubsub_topic.accounting[each.value.topic].id
  filter                     = each.value.filter
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
    push_endpoint = "${var.microservice_urls[each.value.target]}/internal/events"
    oidc_token {
      service_account_email = google_service_account.micro["pubsub-push"].email
      audience              = var.microservice_urls[each.value.target]
    }
  }
  expiration_policy { ttl = "" }
  depends_on = [google_cloud_run_v2_service_iam_member.micro, google_service_account_iam_member.pubsub_token_creator]
}
resource "google_pubsub_subscription_iam_member" "accounting_dead_letter" {
  for_each     = local.accounting_subscriptions
  project      = var.project_id
  subscription = google_pubsub_subscription.accounting[each.key].id
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:service-${data.google_project.micro[0].number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}
resource "google_cloud_scheduler_job" "accounting" {
  for_each         = local.accounting_services
  project          = var.project_id
  region           = var.region
  name             = "${each.key}-accounting-tick"
  schedule         = "* * * * *"
  time_zone        = "UTC"
  attempt_deadline = "120s"
  retry_config { retry_count = 3 }
  http_target {
    uri         = "${var.microservice_urls[each.key]}/internal/${each.key}/tick"
    http_method = "POST"
    oidc_token {
      service_account_email = google_service_account.micro["outbox-scheduler"].email
      audience              = var.microservice_urls[each.key]
    }
  }
  depends_on = [google_project_service.micro, google_cloud_run_v2_service_iam_member.micro]
}
resource "google_service_account_iam_member" "accounting_builder" {
  for_each           = local.accounting_services
  service_account_id = google_service_account.micro[each.key].name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${var.build_service_account}@${var.project_id}.iam.gserviceaccount.com"
}

# Match the existing services: the builder can update only these named runtimes.
resource "google_cloud_run_v2_service_iam_member" "accounting_deployer" {
  for_each   = local.accounting_services
  project    = var.project_id
  location   = var.region
  name       = "psi-${each.key}"
  role       = "roles/run.developer"
  member     = "serviceAccount:${var.build_service_account}@${var.project_id}.iam.gserviceaccount.com"
  depends_on = [module.microservices]
}
