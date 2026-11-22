output "org_id" {
  description = "The organization's numeric ID."
  value       = var.org_id
}

output "apps_folder" {
  description = "The apps folder (`folders/<id>`), where the pipeline identity's grants stop."
  value       = google_folder.apps.name
}

output "projects" {
  description = "Each project's ID and number, keyed as in var.projects."
  value = {
    for k, p in google_project.this : k => {
      project_id     = p.project_id
      project_number = p.number
    }
  }
}

output "state_bucket" {
  description = "The Terraform state bucket, for every gcs backend's `bucket`."
  value       = google_storage_bucket.tfstate.name
}

output "workload_identity_provider" {
  description = "The full provider name google-github-actions/auth takes as `workload_identity_provider` (github-repos sets it as GCP_WORKLOAD_IDENTITY_PROVIDER)."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "workload_identity_pool" {
  description = "The pool's full name, for `principal://iam.googleapis.com/<this>/subject/<subject>` bindings."
  value       = google_iam_workload_identity_pool.github.name
}

output "pipeline_service_account" {
  description = "This repo's apply identity (GCP_SERVICE_ACCOUNT on its `apply` environment)."
  value       = google_service_account.pipeline.email
}
