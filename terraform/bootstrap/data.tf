# For the directory customer ID (C0...) iam.allowedPolicyMemberDomains names.
data "google_organization" "this" {
  organization = "organizations/${var.org_id}"
}
