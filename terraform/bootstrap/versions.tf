terraform {
  # 1.7: `for_each` on import blocks (main.policy.tf adopts the org policies
  # Google sets on a new organization) and mock_resource in the tests.
  required_version = ">= 1.7"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
  }

  # No backend block, deliberately, as in azure-landingzone's bootstrap: this
  # component creates the bucket every other component keeps its state in, so
  # it cannot keep its own there without a bootstrap destroy deleting the state
  # it is running from. Every name here is a literal in terraform.tfvars, so
  # lost state costs one `terraform import` per resource, not an outage.
}

# Projects and their APIs. Personal credentials bill these calls to the quota
# project `gcloud auth application-default set-quota-project` names, which the
# README's first-apply steps set to the platform project.
provider "google" {}

# Everything else, billed explicitly to the platform project: Org Policy,
# Billing Budgets and IAM refuse a personal call that names no quota project.
# Each resource here depends on google_project_service.this, so the API it
# calls is on first.
provider "google" {
  alias                 = "platform"
  billing_project       = var.projects["platform"].project_id
  user_project_override = true
}
