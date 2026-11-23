# Terraform state for every other component in this repo and for every app on
# GCP, one prefix each (`<repo>/`). One bucket rather than azure-landingzone's
# two accounts: a GCS grant can be conditioned on an object prefix, which is
# what keeps one app out of another's state.
resource "google_storage_bucket" "tfstate" {
  provider = google.platform

  # checkov:skip=CKV_GCP_62: no access logging. It would log every plan's
  #   reads, to tell us the pipeline read its state.
  name     = var.state_bucket_name
  project  = local.platform_project
  location = upper(var.region)

  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # Every state write is a version, so a bad apply's state can be rolled back.
  versioning {
    enabled = true
  }

  # A deleted or overwritten object stays recoverable for 30 days (the
  # default is 7).
  soft_delete_policy {
    retention_duration_seconds = 30 * 24 * 60 * 60
  }

  # Keep the last 20 versions of each state file, which is months of applies.
  lifecycle_rule {
    condition {
      num_newer_versions = 20
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  labels = local.labels

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [google_project_service.this]
}

# Each app's deploy identity (main.apps.tf) reaches its own prefix and nothing
# else. The grant lives here, applied by a person, so nothing CI applies can
# widen access to state.
resource "google_storage_bucket_iam_member" "consumer_state" {
  provider = google.platform
  for_each = var.apps

  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.objectAdmin"
  member = google_service_account.app_deploy[each.key].member

  condition {
    title       = "${each.key} state only"
    description = "Objects under ${each.key}/"
    expression  = "resource.name.startsWith(\"projects/_/buckets/${google_storage_bucket.tfstate.name}/objects/${each.key}/\")"
  }
}

# Listing is checked against the bucket, so the prefix condition above cannot
# allow it, and the gcs backend lists objects to find workspaces. It shows
# object names, not contents.
resource "google_storage_bucket_iam_member" "consumer_state_list" {
  provider = google.platform
  for_each = var.apps

  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.legacyBucketReader"
  member = google_service_account.app_deploy[each.key].member
}
