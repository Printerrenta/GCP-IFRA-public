output "repository_name" {
  value = google_artifact_registry_repository.this.name
}

output "docker_repository_url" {
  description = "Registry path prefix used when tagging images."
  value       = "${google_artifact_registry_repository.this.location}-docker.pkg.dev/${google_artifact_registry_repository.this.project}/${google_artifact_registry_repository.this.repository_id}"
}

output "cleanup_policy_ids" {
  description = "Configured Artifact Registry cleanup policy IDs."
  value       = toset([for policy in google_artifact_registry_repository.this.cleanup_policies : policy.id])
}
