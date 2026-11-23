terraform {
  # 1.9: org_policies_to_adopt's validation refers to a local. (1.7 brought
  # `for_each` on import blocks and mock_resource in the tests.)
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
  }

  # In the bucket this component creates, under its own prefix. Unlike
  # azure-landingzone's bootstrap, which keeps local state so a destroy can't
  # delete the state it runs from: here the bucket has prevent_destroy, the
  # projects deletion_policy PREVENT, and every object 30 days of soft delete,
  # so that risk is covered, and a local file is the bigger one.
  #
  # `bootstrap/`, not `gcp-landingzone/`: the pipeline identity's grant covers
  # only the latter, so it can neither read nor write this state. Only a
  # person (the projects' owners) can.
  #
  # A fresh organization has no bucket yet: the first apply runs with a
  # gitignored backend_override.tf forcing local state, then migrates. See
  # the README's "Manual steps".
  backend "gcs" {
    # var.state_bucket_name, as a literal: a backend can't read variables.
    bucket = "jaywithers-tfstate"
    prefix = "bootstrap"
  }
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
