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

# Mocked service accounts all take the platform alias' defaults above, so
# health's deploy identity is set to look like its own.
override_resource {
  target = google_service_account.app_deploy["health"]
  values = {
    email  = "health-deploy@jaywithers-health-dev.iam.gserviceaccount.com"
    member = "serviceAccount:health-deploy@jaywithers-health-dev.iam.gserviceaccount.com"
    name   = "projects/jaywithers-health-dev/serviceAccounts/health-deploy@jaywithers-health-dev.iam.gserviceaccount.com"
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
  # Imports cannot run against a mocked provider.
  org_policies_to_adopt = []
}

run "guardrails" {
  command = plan

  assert {
    condition     = google_org_policy_policy.org["gcp.resourceLocations"].spec[0].rules[0].values[0].allowed_values == tolist(["in:europe-west1-locations"])
    error_message = "Resources must be confined to europe-west1."
  }

  # Google enforces the managed constraint on new organizations; managing the
  # legacy one as well would mean two policies for one rule.
  assert {
    condition     = google_org_policy_policy.org["iam.managed.disableServiceAccountKeyCreation"].spec[0].rules[0].enforce == "TRUE"
    error_message = "Service account keys must be forbidden, through the managed constraint."
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
    condition     = google_project.this["platform"].org_id == "668995077740" && google_project.this["platform"].folder_id == null
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

  # Custom roles live in projects and organizations, so GCP refuses
  # roles/iam.roleAdmin on a folder (400 "not supported for this resource").
  assert {
    condition     = !contains(keys(google_folder_iam_member.pipeline), "roles/iam.roleAdmin")
    error_message = "roles/iam.roleAdmin cannot be granted on a folder."
  }

  assert {
    condition     = google_project_iam_member.pipeline_apps["health/roles/iam.roleAdmin"].project == "jaywithers-health-dev"
    error_message = "The pipeline needs roles/iam.roleAdmin on each app project, for foundation's custom roles there."
  }

  assert {
    condition     = !contains(keys(google_project_iam_member.pipeline_apps), "platform/roles/iam.roleAdmin")
    error_message = "Only app projects get the per-project roles."
  }

  assert {
    condition     = google_storage_bucket_iam_member.pipeline_state.condition[0].expression == "resource.name.startsWith(\"projects/_/buckets/jaywithers-tfstate/objects/gcp-landingzone/\")"
    error_message = "The pipeline identity reaches its own state prefix only."
  }
}

run "apps" {
  command = apply

  assert {
    condition     = google_service_account.app_deploy["health"].project == "jaywithers-health-dev" && google_service_account.app_deploy["health"].account_id == "health-deploy"
    error_message = "health's deploy identity lives in its own project."
  }

  assert {
    condition     = endswith(google_service_account_iam_member.app_deploy_federation["health"].member, "/subject/repo:jay-withers@288264678/health@1377247331:environment:dev")
    error_message = "health's deploy identity trusts its dev environment's subject alone."
  }

  assert {
    condition     = google_storage_bucket_iam_member.consumer_state["health"].condition[0].expression == "resource.name.startsWith(\"projects/_/buckets/jaywithers-tfstate/objects/health/\")"
    error_message = "health's pipeline reaches health/ only."
  }

  assert {
    condition     = google_storage_bucket_iam_member.consumer_state["health"].member == "serviceAccount:health-deploy@jaywithers-health-dev.iam.gserviceaccount.com"
    error_message = "health's state grant goes to its deploy identity."
  }

  assert {
    condition     = alltrue([for k, g in google_project_iam_member.app_deploy : g.project == "jaywithers-health-dev"])
    error_message = "An app's deploy identity holds roles on its own project only."
  }

  assert {
    condition     = !anytrue([for k, g in google_project_iam_member.app_deploy : contains(["roles/owner", "roles/editor", "roles/resourcemanager.projectIamAdmin"], g.role)])
    error_message = "An app's deploy identity never holds owner, editor or project IAM admin."
  }

  assert {
    condition     = google_iam_deny_policy.no_bucket_delete["health"].rules[0].deny_rule[0].denied_permissions == tolist(["storage.googleapis.com/buckets.delete"])
    error_message = "Buckets in an app project can't be deleted while the deny policy stands."
  }
}

# A legacy name for a constraint the organization holds as a managed one is
# refused at plan, before any import is attempted.
run "adopt_unmanaged_constraint" {
  command = plan

  variables {
    org_policies_to_adopt = ["iam.disableServiceAccountKeyCreation"]
  }

  expect_failures = [var.org_policies_to_adopt]
}

# bootstrap/ is bootstrap's own state: no app pipeline may be granted it.
run "bootstrap_prefix_is_reserved" {
  command = plan

  variables {
    apps = {
      bootstrap = {
        project = "health"
        subject = "repo:jay-withers@288264678/some-repo@1:environment:dev"
      }
    }
  }

  expect_failures = [var.apps]
}

# An app belongs in an app project, never the platform one.
run "app_not_in_platform" {
  command = plan

  variables {
    apps = {
      someapp = {
        project = "platform"
        subject = "repo:jay-withers@288264678/some-repo@1:environment:dev"
      }
    }
  }

  expect_failures = [var.apps]
}
