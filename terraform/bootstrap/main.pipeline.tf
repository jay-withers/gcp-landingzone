# This repo's own CI apply identity: what cd-terraform will sign in as for
# every component except this one.
#
# Created here, in bootstrap, because bootstrap is never applied from CI (and
# its state, under bootstrap/, is outside this identity's prefix grant), so no
# pipeline apply can delete, re-bind or re-scope the identity it runs as. The same reasoning as azure-landingzone's
# uai-azure-landingzone-apply-dev.
#
# What keeps it to merged code: the binding trusts only the `apply` GitHub
# environment's subject, which github-repos restricts to main. Pull requests
# get no credentialled plan.
#
# Its rights stop at reading the apps folder, the platform project (for
# foundation's Artifact Registry proxy) and its own state prefix. It cannot touch org policy, create projects or folders, link billing,
# or change who can read state.
resource "google_service_account" "pipeline" {
  provider = google.platform

  project      = local.platform_project
  account_id   = "gcp-landingzone-apply"
  display_name = "gcp-landingzone apply"
  description  = "cd-terraform for gcp-landingzone's pipeline-applied components (GitHub environment `apply`, main only)"

  depends_on = [google_project_service.this]
}

resource "google_service_account_iam_member" "pipeline_federation" {
  provider = google.platform

  service_account_id = google_service_account.pipeline.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/subject/${var.pipeline_identity.subject}"
}

resource "google_folder_iam_member" "pipeline" {
  provider = google.platform
  for_each = local.pipeline_folder_roles

  folder = google_folder.apps.name
  role   = each.key
  member = google_service_account.pipeline.member
}

resource "google_project_iam_member" "pipeline_platform" {
  provider = google.platform
  for_each = local.pipeline_platform_roles

  project = local.platform_project
  role    = each.key
  member  = google_service_account.pipeline.member
}

# Its own state: objects under its own prefix only, plus listing (which GCS
# checks against the bucket, not an object, so a prefix condition cannot cover
# it). No right over the bucket or its IAM: each app's state grant is made in
# main.state.tf, by hand, so nothing applied from CI can widen access to state.
resource "google_storage_bucket_iam_member" "pipeline_state" {
  provider = google.platform

  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.objectAdmin"
  member = google_service_account.pipeline.member

  condition {
    title       = "gcp-landingzone state only"
    description = "Objects under gcp-landingzone/"
    expression  = "resource.name.startsWith(\"projects/_/buckets/${google_storage_bucket.tfstate.name}/objects/gcp-landingzone/\")"
  }
}

resource "google_storage_bucket_iam_member" "pipeline_state_list" {
  provider = google.platform

  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.legacyBucketReader"
  member = google_service_account.pipeline.member
}
