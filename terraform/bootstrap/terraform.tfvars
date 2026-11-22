# Not secret: none of these grant anything on their own. Every one is tied to
# this organization and billing account (tenant literals).

org_id          = "668995077740"
billing_account = "01B172-6360A2-5D15E2"

region            = "europe-west1"
allowed_locations = ["in:europe-west1-locations"]

projects = {
  platform = {
    project_id     = "jaywithers-platform"
    name           = "platform"
    in_apps_folder = false
    services = [
      "artifactregistry.googleapis.com",
      "billingbudgets.googleapis.com",
      "cloudbilling.googleapis.com",
      "cloudresourcemanager.googleapis.com",
      "iam.googleapis.com",
      "iamcredentials.googleapis.com",
      "orgpolicy.googleapis.com",
      "serviceusage.googleapis.com",
      "storage.googleapis.com",
      "sts.googleapis.com",
    ]
  }

  # Cloud Run service and jobs, Scheduler, Secret Manager and the log bucket.
  health = {
    project_id = "jaywithers-health-dev"
    name       = "health-dev"
    services = [
      "cloudresourcemanager.googleapis.com",
      "cloudscheduler.googleapis.com",
      "iam.googleapis.com",
      "iamcredentials.googleapis.com",
      "logging.googleapis.com",
      "monitoring.googleapis.com",
      "run.googleapis.com",
      "secretmanager.googleapis.com",
      "serviceusage.googleapis.com",
      "storage.googleapis.com",
    ]
  }
}

# health's Cloud Run service is open to the internet; its passcode gate is the
# front door.
public_invoker_projects = ["health"]

# Set by Google on the new organization, so the first apply imports them:
# the ones bootstrap manages out of `gcloud org-policies list` on 2026-11-22.
# Google also set essentialcontacts.managed.allowedContactDomains and
# compute.managed.restrictProtocolForwardingCreationForTypes, which bootstrap
# leaves alone. Empty this after that apply.
org_policies_to_adopt = [
  "iam.allowedPolicyMemberDomains",
  "iam.automaticIamGrantsForDefaultServiceAccounts",
  "iam.disableServiceAccountKeyUpload",
  "iam.managed.disableServiceAccountKeyCreation",
  "storage.uniformBucketLevelAccess",
]

github_owner_id = "288264678"

pipeline_identity = {
  subject = "repo:jay-withers@288264678/gcp-landingzone@1467951828:environment:apply"
}

state_bucket_name = "jaywithers-tfstate"

# health's pipeline plans and applies in its `dev` GitHub environment.
state_consumers = {
  health = {
    subject = "repo:jay-withers@288264678/health@1377247331:environment:dev"
  }
}

budget_amount = 5
