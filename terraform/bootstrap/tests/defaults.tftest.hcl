# Mocked providers: no Google credentials, nothing created. Checks the shape of
# what bootstrap would build from terraform.tfvars.

mock_provider "google" {}

mock_provider "google" {
  alias = "platform"

  # IAM members are validated even against a mock, so the generated values
  # must look real.
  mock_resource "google_service_account" {
    defaults = {
      email  = "gcp-landingzone-apply@jaywithers-platform.iam.gserviceaccount.com"
      member = "serviceAccount:gcp-landingzone-apply@jaywithers-platform.iam.gserviceaccount.com"
      name   = "projects/jaywithers-platform/serviceAccounts/gcp-landingzone-apply@jaywithers-platform.iam.gserviceaccount.com"
    }
  }

  mock_resource "google_iam_workload_identity_pool" {
    defaults = {
      name = "projects/123456789/locations/global/workloadIdentityPools/github"
    }
  }

  mock_resource "google_project_iam_custom_role" {
    defaults = {
      name = "projects/jaywithers-platform/roles/tfstateIamAdmin"
    }
  }
}

# main.tf imports the platform project, and a mock provider cannot import.
override_resource {
  target = google_project.this["platform"]
  values = {
    number = "123456789"
  }
}

variables {
  # A real ID is needed for validation only; nothing is called.
  org_id = "123456789012"
  # Imports cannot run against a mocked provider.
  org_policies_to_adopt = []
}

run "guardrails" {
  command = plan

  assert {
    condition     = google_org_policy_policy.org["gcp.resourceLocations"].spec[0].rules[0].values[0].allowed_values == tolist(["in:europe-west1-locations"])
    error_message = "Resources must be confined to europe-west1."
  }

  assert {
    condition     = google_org_policy_policy.org["iam.disableServiceAccountKeyCreation"].spec[0].rules[0].enforce == "TRUE"
    error_message = "Service account keys must be forbidden."
  }

  assert {
    condition     = keys(google_org_policy_policy.public_invoker) == ["health"]
    error_message = "Only health may grant allUsers."
  }

  assert {
    condition     = google_org_policy_policy.public_invoker["health"].spec[0].inherit_from_parent == false
    error_message = "health's exemption must not inherit the domain restriction."
  }
}

run "projects" {
  command = plan

  assert {
    condition     = google_project.this["platform"].org_id == "123456789012" && google_project.this["platform"].folder_id == null
    error_message = "The platform project sits at the organization root."
  }

  assert {
    condition     = google_project.this["health"].org_id == null
    error_message = "App projects sit in the apps folder."
  }

  assert {
    condition     = alltrue([for p in google_project.this : p.auto_create_network == false && p.deletion_policy == "PREVENT"])
    error_message = "No project gets a default network, and none can be deleted by Terraform."
  }
}

# Applied against the mocks, because the binding's member embeds the pool's
# name, which is only known after apply.
run "pipeline" {
  command = apply

  assert {
    condition     = google_iam_workload_identity_pool_provider.github.attribute_condition == "assertion.repository_owner_id == \"288264678\""
    error_message = "The pool must accept jay-withers tokens only."
  }

  assert {
    condition     = endswith(google_service_account_iam_member.pipeline_federation.member, "/subject/repo:jay-withers@288264678/gcp-landingzone@1467951828:environment:apply")
    error_message = "The apply identity must trust the main-only apply environment alone."
  }

  assert {
    condition     = !contains(keys(google_folder_iam_member.pipeline), "roles/owner") && !contains(keys(google_folder_iam_member.pipeline), "roles/resourcemanager.projectCreator")
    error_message = "The pipeline identity must not be able to own or create projects."
  }

  assert {
    condition     = google_storage_bucket_iam_member.pipeline_state.condition[0].expression == "resource.name.startsWith(\"projects/_/buckets/jaywithers-tfstate/objects/gcp-landingzone/\")"
    error_message = "The pipeline identity reaches its own state prefix only."
  }
}

run "state_consumers" {
  command = apply

  assert {
    condition     = google_storage_bucket_iam_member.consumer_state["health"].condition[0].expression == "resource.name.startsWith(\"projects/_/buckets/jaywithers-tfstate/objects/health/\")"
    error_message = "health's pipeline reaches health/ only."
  }

  assert {
    condition     = endswith(google_storage_bucket_iam_member.consumer_state["health"].member, "/subject/repo:jay-withers@288264678/health@1377247331:environment:dev")
    error_message = "health's state grant names its dev environment's subject."
  }
}
