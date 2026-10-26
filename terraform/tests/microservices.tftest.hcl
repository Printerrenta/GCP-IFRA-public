mock_provider "google" {
  mock_data "google_project" {
    defaults = { number = "123456789012" }
  }
}
run "private_microservice_plan" {
  command = plan
  variables {
    project_id              = "printer-rental-example"
    environment             = "dev"
    container_image         = "europe-west1-docker.pkg.dev/printer-rental-example/printer-rental-images/api-gateway:test"
    runtime_service_account = "psi-gateway@printer-rental-example.iam.gserviceaccount.com"
    runtime_environment = {
      IDENTITY_SERVICE_URL     = "https://identity.example.com"
      RENTAL_SERVICE_URL       = "https://rental.example.com"
      DOCUMENT_SERVICE_URL     = "https://documents.example.com"
      NOTIFICATION_SERVICE_URL = "https://notifications.example.com"
    }
    runtime_secrets              = {}
    microservices_enabled        = true
    independent_delivery_enabled = true
    microservice_images = {
      identity      = "europe-west1-docker.pkg.dev/printer-rental-example/printer-rental-images/identity-service:test"
      rental        = "europe-west1-docker.pkg.dev/printer-rental-example/printer-rental-images/rental-service:test"
      documents     = "europe-west1-docker.pkg.dev/printer-rental-example/printer-rental-images/document-service:test"
      notifications = "europe-west1-docker.pkg.dev/printer-rental-example/printer-rental-images/notification-service:test"
    }
    microservice_urls            = { identity = "https://identity.example.com", rental = "https://rental.example.com", documents = "https://documents.example.com", notifications = "https://notifications.example.com" }
    neon_auth_environment        = { NEON_AUTH_BASE_URL = "https://auth.test/auth", NEON_AUTH_JWKS_URL = "https://auth.test/jwks" }
    document_storage_environment = { AWS_ENDPOINT_URL_S3 = "https://storage.test", AWS_REGION = "eu-central-1", STORAGE_BUCKET = "assets" }
  }
  assert {
    condition     = length(module.microservices) == 4 && length(google_service_account.micro) == 7
    error_message = "Four domain services and seven isolated runtime/trigger identities are required."
  }
  assert {
    condition     = length(var.runtime_secrets) == 0 && length(google_cloud_run_v2_service_iam_member.micro) == 10
    error_message = "Gateway must be secret-free and all invocation edges explicitly scoped."
  }
  assert {
    condition     = google_pubsub_subscription.notifications[0].dead_letter_policy[0].max_delivery_attempts == 10
    error_message = "Authenticated event delivery requires the configured dead-letter policy."
  }
  assert {
    condition     = length(google_cloudbuild_trigger.service) == 5 && length(google_cloudbuildv2_repository.service) == 5
    error_message = "Each service must have its own repository and deployment trigger."
  }
  assert {
    condition     = google_cloudbuild_trigger.legacy_backend[0].disabled && alltrue([for trigger in google_cloudbuild_trigger.service : trigger.repository_event_config[0].push[0].branch == "^main$" && trigger.filename == "cloudbuild.yaml" && !trigger.disabled])
    error_message = "Only main branches deploy; the retired monorepo deployment must remain disabled."
  }
}

run "other_environments_remain_isolated" {
  command = plan
  variables {
    project_id      = "printer-rental-example"
    environment     = "acc"
    container_image = "europe-west1-docker.pkg.dev/printer-rental-example/printer-rental-acc/api-gateway:test"
  }
  assert {
    condition     = length(module.microservices) == 0 && length(google_cloudbuild_trigger.service) == 0 && length(google_cloudbuild_trigger.legacy_backend) == 0
    error_message = "Acc/prod must not inherit dev microservices or deployment triggers implicitly."
  }
}
run "independent_delivery_requires_services" {
  command = plan
  variables {
    project_id                   = "printer-rental-example"
    environment                  = "dev"
    container_image              = "europe-west1-docker.pkg.dev/printer-rental-example/printer-rental-images/api-gateway:test"
    independent_delivery_enabled = true
    microservices_enabled        = false
  }
  expect_failures = [var.independent_delivery_enabled]
}

run "private_accounting_plan" {
  command = plan
  variables {
    project_id              = "printer-rental-example"
    environment             = "dev"
    container_image         = "europe-west1-docker.pkg.dev/printer-rental-example/printer-rental-images/api-gateway:test"
    runtime_service_account = "psi-gateway@printer-rental-example.iam.gserviceaccount.com"
    runtime_environment = {
      IDENTITY_SERVICE_URL     = "https://identity.example.com"
      RENTAL_SERVICE_URL       = "https://rental.example.com"
      DOCUMENT_SERVICE_URL     = "https://documents.example.com"
      NOTIFICATION_SERVICE_URL = "https://notifications.example.com"
    }
    runtime_secrets              = {}
    microservices_enabled        = true
    independent_delivery_enabled = true
    microservice_images = {
      identity      = "europe-west1-docker.pkg.dev/printer-rental-example/printer-rental-images/identity-service:test"
      rental        = "europe-west1-docker.pkg.dev/printer-rental-example/printer-rental-images/rental-service:test"
      documents     = "europe-west1-docker.pkg.dev/printer-rental-example/printer-rental-images/document-service:test"
      notifications = "europe-west1-docker.pkg.dev/printer-rental-example/printer-rental-images/notification-service:test"
      metering      = "europe-west1-docker.pkg.dev/printer-rental-example/printer-rental-images/metering-service:test"
      billing       = "europe-west1-docker.pkg.dev/printer-rental-example/printer-rental-images/billing-service:test"
    }
    microservice_urls            = { identity = "https://identity.example.com", rental = "https://rental.example.com", documents = "https://documents.example.com", notifications = "https://notifications.example.com", metering = "https://metering.example.com", billing = "https://billing.example.com" }
    neon_auth_environment        = { NEON_AUTH_BASE_URL = "https://auth.test/auth", NEON_AUTH_JWKS_URL = "https://auth.test/jwks" }
    document_storage_environment = { AWS_ENDPOINT_URL_S3 = "https://storage.test", AWS_REGION = "eu-central-1", STORAGE_BUCKET = "assets" }
    accounting_enabled           = true
  }
  assert {
    condition     = length(module.microservices) == 6 && length(google_service_account.micro) == 9 && length(google_cloudbuild_trigger.service) == 7
    error_message = "Accounting must add two independent services/identities and deployment triggers."
  }
  assert {
    condition     = length(google_pubsub_subscription.accounting) == 5 && length(google_pubsub_topic.accounting) == 2 && length(google_cloud_scheduler_job.accounting) == 2
    error_message = "Accounting needs its own topics, authenticated subscriptions and private durable heartbeats."
  }
  assert {
    condition     = length(google_cloud_run_v2_service_iam_member.micro) == 20 && alltrue([for s in google_pubsub_subscription.accounting : s.dead_letter_policy[0].max_delivery_attempts == 10])
    error_message = "All service invocation edges and dead-letter policies must remain scoped."
  }
  assert {
    condition     = length(var.runtime_secrets) == 0 && length(local.micro_secrets["metering"]) == 2 && length(local.micro_secrets["billing"]) == 2
    error_message = "Gateway must remain secret-free and new domains may receive only their two database URLs."
  }
  assert {
    condition     = length(google_cloud_run_v2_service_iam_member.accounting_deployer) == 2 && toset([for b in google_cloud_run_v2_service_iam_member.accounting_deployer : b.name]) == toset(["psi-metering", "psi-billing"]) && alltrue([for b in google_cloud_run_v2_service_iam_member.accounting_deployer : b.role == "roles/run.developer" && b.member == "serviceAccount:psi-be-build@printer-rental-example.iam.gserviceaccount.com"])
    error_message = "Only the two new runtimes may grant the existing builder service-scoped deployment access."
  }
}

run "separate_database_secret_pins" {
  command = plan
  variables {
    project_id              = "printer-rental-example"
    environment             = "dev"
    container_image         = "europe-west1-docker.pkg.dev/printer-rental-example/printer-rental-images/api-gateway:test"
    runtime_service_account = "psi-gateway@printer-rental-example.iam.gserviceaccount.com"
    runtime_environment = {
      IDENTITY_SERVICE_URL     = "https://identity.example.com"
      RENTAL_SERVICE_URL       = "https://rental.example.com"
      DOCUMENT_SERVICE_URL     = "https://documents.example.com"
      NOTIFICATION_SERVICE_URL = "https://notifications.example.com"
    }
    runtime_secrets              = {}
    microservices_enabled        = true
    independent_delivery_enabled = true
    microservice_images = {
      identity      = "europe-west1-docker.pkg.dev/printer-rental-example/printer-rental-images/identity-service:test"
      rental        = "europe-west1-docker.pkg.dev/printer-rental-example/printer-rental-images/rental-service:test"
      documents     = "europe-west1-docker.pkg.dev/printer-rental-example/printer-rental-images/document-service:test"
      notifications = "europe-west1-docker.pkg.dev/printer-rental-example/printer-rental-images/notification-service:test"
      metering      = "europe-west1-docker.pkg.dev/printer-rental-example/printer-rental-images/metering-service:test"
      billing       = "europe-west1-docker.pkg.dev/printer-rental-example/printer-rental-images/billing-service:test"
    }
    microservice_urls            = { identity = "https://identity.example.com", rental = "https://rental.example.com", documents = "https://documents.example.com", notifications = "https://notifications.example.com", metering = "https://metering.example.com", billing = "https://billing.example.com" }
    neon_auth_environment        = { NEON_AUTH_BASE_URL = "https://auth.test/auth", NEON_AUTH_JWKS_URL = "https://auth.test/jwks" }
    document_storage_environment = { AWS_ENDPOINT_URL_S3 = "https://storage.test", AWS_REGION = "eu-central-1", STORAGE_BUCKET = "assets" }
    accounting_enabled           = true

    service_database_secret_versions = {
      identity      = { pooled = "2", direct = "3" }
      rental        = { pooled = "2", direct = "3" }
      documents     = { pooled = "2", direct = "3" }
      notifications = { pooled = "2", direct = "3" }
      metering      = { pooled = "2", direct = "3" }
      billing       = { pooled = "2", direct = "3" }
    }
  }
  assert {
    condition = alltrue([for service in ["identity", "rental", "documents", "notifications", "metering", "billing"] :
      local.micro_secrets[service].DATABASE_URL.version == "2" &&
      local.micro_secrets[service].DATABASE_URL_UNPOOLED.version == "3"
    ])
    error_message = "All six services must retain the reviewed new DB secret versions on future applies."
  }
  assert {
    condition     = length(google_secret_manager_secret_iam_member.micro) == 14 && length(module.microservices) == 6 && local.micro_secrets["documents"].AWS_ACCESS_KEY_ID.version == "1"
    error_message = "Database URL pins must not add IAM grants, services or change storage credentials."
  }
}
run "reject_mutable_database_secret_version" {
  command = plan
  variables {
    project_id                       = "printer-rental-example"
    environment                      = "dev"
    container_image                  = "example.invalid/image:test"
    service_database_secret_versions = { rental = { pooled = "latest", direct = "2" } }
  }
  expect_failures = [var.service_database_secret_versions]
}
run "reject_gateway_database_secret" {
  command = plan
  variables {
    project_id                       = "printer-rental-example"
    environment                      = "dev"
    container_image                  = "example.invalid/image:test"
    service_database_secret_versions = { gateway = { pooled = "2", direct = "2" } }
  }
  expect_failures = [var.service_database_secret_versions]
}
