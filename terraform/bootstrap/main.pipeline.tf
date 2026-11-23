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
# Its rights stop at the apps folder, each app project (for the one role GCP
# refuses on a folder: see local.pipeline_app_project_roles), the platform
# project and its own state prefix. It cannot touch org policy, create projects or folders, link billing,
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
  # checkov:skip=CKV_GCP_44: serviceAccountAdmin on the apps folder is how
  #   foundation creates each app's deploy identity and binds it to that
  #   app's GitHub environment. It is the apply identity, the deliberate
  #   exception to targeted grants, as in azure-landingzone; it stops at the
  #   folder, so the platform project's own identities stay out of reach.
  provider = google.platform
  for_each = local.pipeline_folder_roles

  folder = google_folder.apps.name
  role   = each.key
  member = google_service_account.pipeline.member
}

resource "google_project_iam_member" "pipeline_apps" {
  provider = google.platform
  for_each = local.pipeline_app_project_roles

  project = google_project.this[each.value.project].project_id
  role    = each.value.role
  member  = google_service_account.pipeline.member
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
