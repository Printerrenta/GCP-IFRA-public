variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "service_name" {
  type = string
}

variable "container_image" {
  type = string
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "min_instance_count" {
  type    = number
  default = 0
}

variable "max_instance_count" {
  type    = number
  default = 3
}

variable "allow_unauthenticated" {
  type    = bool
  default = false
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "runtime_service_account" {
  type    = string
  default = null
}

variable "runtime_environment" {
  type    = map(string)
  default = {}
}

variable "runtime_secrets" {
  type    = map(object({ secret = string, version = string }))
  default = {}
}

variable "container_memory" {
  type    = string
  default = null
}

variable "startup_cpu_boost" {
  description = "Preserve the configured startup CPU boost independently of request-based billing."
  type        = bool
  default     = false
}
