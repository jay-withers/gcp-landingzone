# The organization's shape: one folder for apps, the platform project at the
# root beside it, and one project per app inside it.
#
# Projects and the folder are created by whoever applies this, by hand, as an
# organization administrator. The pipeline identity cannot create, move or
# delete either: its grants stop at the folder (main.pipeline.tf).

resource "google_folder" "apps" {
  display_name = "apps"
  parent       = "organizations/${var.org_id}"

  # Deleting a folder needs it empty anyway; this makes Terraform refuse too.
  deletion_protection = true
}

# The platform project is made with gcloud before the first apply (see the
# README) and adopted here: until it exists there is no quota project for
# personal credentials, and nothing on the google.platform alias can even be
# planned. A no-op once it is in state.
import {
  to = google_project.this["platform"]
  id = var.projects["platform"].project_id
}

resource "google_project" "this" {
  # checkov:skip=CKV2_GCP_5: no Data Access audit logs. Admin Activity logs
  #   (who changed what) are always on and free; Data Access logs would record
  #   every read of a training log and every state fetch, billed past the free
  #   allotment, to say nothing anyone acts on.
  for_each = var.projects

  project_id      = each.value.project_id
  name            = each.value.name
  org_id          = each.value.in_apps_folder ? null : var.org_id
  folder_id       = each.value.in_apps_folder ? google_folder.apps.folder_id : null
  billing_account = var.billing_account

  # Stated as well as enforced by compute.skipDefaultNetworkCreation. The
  # policies cannot come first: their API calls are billed to the platform
  # project, so they wait for it, and a project created in the same first
  # apply may beat them. The other guardrails that matter at creation are
  # among those Google sets on every new organization anyway.
  auto_create_network = false

  # A project delete is recoverable for 30 days, but its ID never is, and
  # health's holds the training log. Lifting this is a deliberate edit.
  deletion_policy = "PREVENT"

  labels = local.labels
}

resource "google_project_service" "this" {
  for_each = local.project_services

  project = google_project.this[each.value.project].project_id
  service = each.value.service

  # Turning an API off can delete what uses it. Removing one from tfvars stops
  # managing it, nothing more.
  disable_on_destroy = false
}
