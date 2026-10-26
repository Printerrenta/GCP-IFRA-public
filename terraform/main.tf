locals {
  name_prefix = "${var.service_name}-${var.environment}"
  labels = {
    application = var.service_name
    environment = var.environment
    managed-by  = "terraform"
  }
}

module "artifact_registry" {
  source = "./modules/artifact-registry"

  project_id    = var.project_id
  location      = var.region
  repository_id = local.name_prefix
  labels        = local.labels
}

module "cloud_run" {
  source = "./modules/cloud-run"

  project_id              = var.project_id
  region                  = var.region
  service_name            = local.name_prefix
  container_image         = var.container_image
  container_port          = var.container_port
  min_instance_count      = var.min_instance_count
  max_instance_count      = var.max_instance_count
  allow_unauthenticated   = var.allow_unauthenticated
  runtime_service_account = var.runtime_service_account
  runtime_environment     = var.runtime_environment
  runtime_secrets         = var.runtime_secrets
  container_memory        = var.container_memory
  labels                  = local.labels
}

output "artifact_registry_repository" {
  description = "Artifact Registry repository path for application images."
  value       = module.artifact_registry.repository_name
}

output "cloud_run_url" {
  description = "Cloud Run service URL."
  value       = module.cloud_run.uri
}
