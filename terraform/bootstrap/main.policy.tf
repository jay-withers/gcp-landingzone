# Organization policy, the counterpart of azure-landingzone's governance
# policies. Here rather than in a pipeline-applied component because setting
# org policy is about the most privileged thing in GCP: the pipeline identity
# never holds roles/orgpolicy.policyAdmin.
#
# Google sets several of these on every organization created since 2024
# ("secure by default"). Those are imported, not created: list them in
# var.org_policies_to_adopt for the first apply.

import {
  for_each = var.org_policies_to_adopt

  to = google_org_policy_policy.org[each.key]
  id = "organizations/${var.org_id}/policies/${each.key}"
}

resource "google_org_policy_policy" "org" {
  provider = google.platform
  for_each = local.org_policies

  name   = "organizations/${var.org_id}/policies/${each.key}"
  parent = "organizations/${var.org_id}"

  spec {
    rules {
      enforce = each.value.enforce ? "TRUE" : null

      dynamic "values" {
        for_each = length(each.value.allowed_values) > 0 ? [each.value.allowed_values] : []
        content {
          allowed_values = values.value
        }
      }
    }
  }

  depends_on = [google_project_service.this]
}

# The one exception. A Cloud Run service open to the internet needs allUsers
# as its invoker, which iam.allowedPolicyMemberDomains forbids. Per project,
# so no other project can make anything public.
resource "google_org_policy_policy" "public_invoker" {
  provider = google.platform
  for_each = var.public_invoker_projects

  name   = "projects/${google_project.this[each.key].project_id}/policies/iam.allowedPolicyMemberDomains"
  parent = "projects/${google_project.this[each.key].project_id}"

  spec {
    inherit_from_parent = false

    rules {
      allow_all = "TRUE"
    }
  }

  depends_on = [google_project_service.this]
}
