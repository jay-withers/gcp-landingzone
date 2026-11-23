# Each app's deploy identity: what its repo's pipeline signs in as to plan,
# apply and deploy. Here, applied by a person, rather than in a component CI
# applies, because each one is a privileged identity and holds that app's
# state prefix (main.state.tf).
#
# A service account rather than the GitHub principal directly, because a
# Cloud Run domain mapping must be created by a verified owner of the domain
# in Search Console, and only an email can be made one: add
# `<key>-deploy@<project>.iam.gserviceaccount.com` there before the app's
# first apply with a custom domain.
resource "google_service_account" "app_deploy" {
  provider = google.platform
  for_each = var.apps

  project      = google_project.this[each.value.project].project_id
  account_id   = "${each.key}-deploy"
  display_name = "${each.key} deploy"
  description  = "${each.key}'s pipeline: Terraform and make deploy (GitHub ${each.value.subject})"

  depends_on = [google_project_service.this]
}

resource "google_service_account_iam_member" "app_deploy_federation" {
  provider = google.platform
  for_each = var.apps

  service_account_id = google_service_account.app_deploy[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/subject/${each.value.subject}"
}

# Manages the app's runtime service accounts without setIamPolicy, which
# roles/iam.serviceAccountAdmin would include: with it, the deploy identity
# could bind any GitHub subject to itself and step round its environment's
# main-only rules. Granting roles to an account happens on the resource
# (a bucket, a secret, a job), never on the account.
resource "google_project_iam_custom_role" "app_service_accounts" {
  provider = google.platform
  for_each = local.app_projects

  project     = google_project.this[each.key].project_id
  role_id     = "appServiceAccountManager"
  title       = "App service account manager"
  description = "Create, update and delete the app's service accounts; never their IAM policy"
  permissions = [
    "iam.serviceAccounts.create",
    "iam.serviceAccounts.delete",
    "iam.serviceAccounts.disable",
    "iam.serviceAccounts.enable",
    "iam.serviceAccounts.get",
    "iam.serviceAccounts.getIamPolicy",
    "iam.serviceAccounts.list",
    "iam.serviceAccounts.undelete",
    "iam.serviceAccounts.update",
  ]

  depends_on = [google_project_service.this]
}

resource "google_project_iam_member" "app_deploy_service_accounts" {
  provider = google.platform
  for_each = var.apps

  project = google_project.this[each.value.project].project_id
  role    = google_project_iam_custom_role.app_service_accounts[each.value.project].name
  member  = google_service_account.app_deploy[each.key].member
}

resource "google_project_iam_member" "app_deploy" {
  provider = google.platform
  for_each = local.app_deploy_grants

  project = google_project.this[var.apps[each.value.app].project].project_id
  role    = each.value.role
  member  = google_service_account.app_deploy[each.value.app].member
}

# GCP's counterpart of Azure's CanNotDelete lock, and stronger than a role
# without the permission: an IAM deny policy wins over every allow, so no one
# can delete a bucket in an app project (the store of record holding each
# app's data), not even a project owner or an identity that grants itself
# storage.admin. Deleting one means a person removes this policy here first.
#
# Applying it needs roles/iam.denyAdmin (see the README's "Manual steps").
resource "google_iam_deny_policy" "no_bucket_delete" {
  provider = google.platform
  for_each = local.app_projects

  parent       = urlencode("cloudresourcemanager.googleapis.com/projects/${google_project.this[each.key].project_id}")
  name         = "no-bucket-delete"
  display_name = "No bucket deletion: stores of record"

  rules {
    description = "Buckets in an app project hold its data; remove this policy (gcp-landingzone bootstrap) to delete one."
    deny_rule {
      denied_principals  = ["principalSet://goog/public:all"]
      denied_permissions = ["storage.googleapis.com/buckets.delete"]
    }
  }

  depends_on = [google_project_service.this]
}
