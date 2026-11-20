variable "project_id" {
  description = "Google Cloud project ID that owns the resources."
  type        = string
}

variable "region" {
  description = "Google Cloud region for Artifact Registry and Cloud Run."
  type        = string
  default     = "europe-west1"
}

variable "environment" {
  description = "Deployment environment name."
  type        = string

  validation {
    condition     = contains(["dev", "acc", "prod"], var.environment)
    error_message = "Environment must be dev, acc, or prod."
  }
}

variable "service_name" {
  description = "Cloud Run service name."
  type        = string
  default     = "gcp-ifra"
}

variable "container_image" {
  description = "Fully qualified container image URI to deploy to Cloud Run."
  type        = string
}

variable "container_port" {
  description = "Port exposed by the application container."
  type        = number
  default     = 8080
}

variable "min_instance_count" {
  description = "Minimum number of Cloud Run instances kept warm."
  type        = number
  default     = 0
}

variable "max_instance_count" {
  description = "Maximum number of Cloud Run instances."
  type        = number
  default     = 3
}

variable "service_min_instance_count" {
  description = "Minimum number of Cloud Run instances kept warm for each domain microservice."
  type        = number
  default     = 0

  validation {
    condition     = var.service_min_instance_count >= 0
    error_message = "service_min_instance_count must be greater than or equal to 0."
  }
}

variable "service_max_instance_count" {
  description = "Maximum number of Cloud Run instances for each domain microservice."
  type        = number
  default     = 1

  validation {
    condition     = var.service_max_instance_count >= 1 && var.service_max_instance_count >= var.service_min_instance_count
    error_message = "service_max_instance_count must be at least 1 and greater than or equal to service_min_instance_count."
  }
}

variable "allow_unauthenticated" {
  description = "Whether to grant public invoker access to the Cloud Run service."
  type        = bool
  default     = false
}

variable "runtime_service_account" {
  description = "Cloud Run runtime identity; null keeps the platform default."
  type        = string
  default     = null
}

variable "runtime_environment" {
  description = "Non-secret Cloud Run environment values. Never put credentials here."
  type        = map(string)
  default     = {}
}

variable "runtime_secrets" {
  description = "Cloud Run environment names mapped to existing Secret Manager secrets and pinned versions."
  type        = map(object({ secret = string, version = string }))
  default     = {}
}

variable "container_memory" {
  description = "Optional memory limit for the container."
  type        = string
  default     = null
}
