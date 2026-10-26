resource "google_cloud_run_v2_service" "this" {
  project              = var.project_id
  name                 = var.service_name
  location             = var.region
  labels               = var.labels
  invoker_iam_disabled = false

  # Per-service CI owns images and explicit traffic promotion. Terraform owns service settings.
  lifecycle {
    ignore_changes = [template[0].containers[0].image, traffic, client, client_version]
  }

  template {
    service_account                  = var.runtime_service_account
    timeout                          = "120s"
    max_instance_request_concurrency = 40
    scaling {
      min_instance_count = var.min_instance_count
      max_instance_count = var.max_instance_count
    }

    containers {
      image = var.container_image

      dynamic "env" {
        for_each = var.runtime_environment
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = var.runtime_secrets
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value.secret
              version = env.value.version
            }
          }
        }
      }

      dynamic "resources" {
        for_each = var.container_memory == null ? [] : [var.container_memory]
        content {
          limits            = { cpu = "1", memory = resources.value }
          cpu_idle          = true
          startup_cpu_boost = var.startup_cpu_boost
        }
      }

      ports {
        container_port = var.container_port
      }
    }
  }
}

resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  count = var.allow_unauthenticated ? 1 : 0

  project  = var.project_id
  location = google_cloud_run_v2_service.this.location
  name     = google_cloud_run_v2_service.this.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
