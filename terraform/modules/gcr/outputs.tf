output "service_account_email" {
  description = "Email of the GCR pusher service account"
  value       = google_service_account.gcr_pusher.email
}

output "service_account_key" {
  description = "Base64 encoded service account key (sensitive)"
  value       = google_service_account_key.gcr_pusher.private_key
  sensitive   = true
}

output "workload_identity_provider" {
  description = "Full resource name of the Workload Identity Provider for GitHub Actions"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "workload_identity_pool_name" {
  description = "Name of the Workload Identity Pool"
  value       = google_iam_workload_identity_pool.github.name
}
