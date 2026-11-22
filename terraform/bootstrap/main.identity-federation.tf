# How GitHub Actions signs in to GCP: a GitHub token is exchanged for
# short-lived Google credentials, so no service account key exists anywhere
# (and iam.managed.disableServiceAccountKeyCreation means none can).
#
# One pool for the estate. Which repo and environment may act as which service
# account is decided by each service account's own workloadIdentityUser
# binding, on the token's full subject: this repo's below, each app's in
# foundation.
#
# A deleted pool or provider holds its ID for 30 days, so renaming either is a
# month's wait, not an apply.
resource "google_iam_workload_identity_pool" "github" {
  provider = google.platform

  project                   = local.platform_project
  workload_identity_pool_id = "github"
  display_name              = "GitHub Actions"
  description               = "jay-withers repositories' GitHub Actions workflows"

  depends_on = [google_project_service.this]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  # checkov:skip=CKV_GCP_125: the check wants one `assertion.sub` pinned on the
  #   provider, i.e. one provider per repo. Here the pool admits this owner's
  #   tokens only, and each service account's workloadIdentityUser binding
  #   names one full subject (repo id and environment), which is Google's own
  #   recommended shape for a pool shared by several repos.
  provider = google.platform

  project                            = local.platform_project
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-actions"
  display_name                       = "GitHub Actions OIDC"

  # google.subject is the whole token subject, in the immutable form
  # (repo:<owner>@<id>/<repo>@<id>:environment:<env>) every jay-withers repo
  # issues, so a renamed or recreated repo never inherits another's access.
  # Well inside the 127-byte limit.
  attribute_mapping = {
    "google.subject"                = "assertion.sub"
    "attribute.repository_id"       = "assertion.repository_id"
    "attribute.repository_owner_id" = "assertion.repository_owner_id"
    "attribute.environment"         = "assertion.environment"
  }

  # Without a condition any GitHub repository's token would be accepted by the
  # pool (bindings would still refuse it, but nothing should get that far).
  # By owner ID, which survives a rename, not by login.
  attribute_condition = "assertion.repository_owner_id == \"${var.github_owner_id}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}
