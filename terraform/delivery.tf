variable "independent_delivery_enabled" {
  description = "Manage independent service repositories and their existing deployment triggers."
  type        = bool
  default     = false
  validation {
    condition     = !var.independent_delivery_enabled || var.microservices_enabled
    error_message = "Independent delivery requires the microservices configuration."
  }
}
variable "github_connection_name" {
  description = "Existing Cloud Build GitHub App connection; OAuth secrets remain outside this module."
  type        = string
  default     = "printerrenta-github"
}
variable "github_owner" {
  type    = string
  default = "Printerrenta"
}
variable "build_service_account" {
  description = "Existing keyless Cloud Build identity."
  type        = string
  default     = "psi-be-build"
}
locals {
  service_repositories = merge(var.independent_delivery_enabled ? {
    gateway       = "psi-api-gateway"
    identity      = "psi-identity-service"
    rental        = "psi-rental-service"
    documents     = "psi-document-service"
    notifications = "psi-notification-service"
  } : {}, var.accounting_enabled ? { metering = "psi-metering-service", billing = "psi-billing-service" } : {})
  connection_id  = "projects/${var.project_id}/locations/${var.region}/connections/${var.github_connection_name}"
  build_identity = "projects/${var.project_id}/serviceAccounts/${var.build_service_account}@${var.project_id}.iam.gserviceaccount.com"
}
resource "google_cloudbuildv2_repository" "service" {
  for_each          = local.service_repositories
  project           = var.project_id
  location          = var.region
  name              = each.value
  parent_connection = var.github_connection_name
  remote_uri        = "https://github.com/${var.github_owner}/${each.value}.git"
  deletion_policy   = "PREVENT"
}
resource "google_cloudbuild_trigger" "service" {
  for_each        = local.service_repositories
  project         = var.project_id
  location        = var.region
  name            = "${each.value}-${var.environment}"
  description     = "Independent service deployment from ${each.value}"
  filename        = "cloudbuild.yaml"
  disabled        = false
  service_account = local.build_identity
  repository_event_config {
    repository = google_cloudbuildv2_repository.service[each.key].id
    push { branch = "^main$" }
  }
}
resource "google_cloudbuild_trigger" "legacy_backend" {
  count           = var.independent_delivery_enabled ? 1 : 0
  project         = var.project_id
  location        = var.region
  name            = "psi-be-${var.environment}"
  description     = "Retired monorepo deployment; services deploy independently"
  filename        = "cloudbuild.yaml"
  disabled        = true
  service_account = local.build_identity
  repository_event_config {
    repository = "${local.connection_id}/repositories/psi-be"
    push { branch = "^main$" }
  }
}
output "service_deployment_triggers" {
  description = "One independently managed main-branch deployment trigger per service."
  value       = { for name, trigger in google_cloudbuild_trigger.service : name => trigger.id }
}
