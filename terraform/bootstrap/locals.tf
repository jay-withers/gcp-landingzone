locals {
  labels = merge({
    managed-by = "terraform"
    repo       = "gcp-landingzone"
  }, var.labels)

  platform_project = google_project.this["platform"].project_id

  # One entry per project and API, keyed "<project>/<service>".
  project_services = merge([
    for key, p in var.projects : {
      for s in p.services : "${key}/${s}" => {
        project = key
        service = s
      }
    }
  ]...)

  # The organization's guardrails: Azure Policy's counterpart. Boolean
  # constraints enforced, plus two list constraints. Each one is something
  # this estate never needs, so none should ever need an exception except
  # the one in public_invoker_projects.
  org_policies = merge(
    {
      for c in [
        # Workload Identity Federation is the only way in from CI, so no
        # service account ever needs a key that could leak. Creation is the
        # managed constraint, which Google enforces on new organizations in
        # place of iam.disableServiceAccountKeyCreation; managing both would
        # be two policies for one rule.
        "iam.managed.disableServiceAccountKeyCreation",
        "iam.disableServiceAccountKeyUpload",
        # Otherwise a new project's default compute and App Engine service
        # accounts get Editor on the whole project.
        "iam.automaticIamGrantsForDefaultServiceAccounts",
        # No public buckets, and no per-object ACLs to reason about.
        "storage.uniformBucketLevelAccess",
        "storage.publicAccessPrevention",
        # No default VPC with its permissive firewall rules in new projects.
        "compute.skipDefaultNetworkCreation",
      ] : c => { enforce = true, allowed_values = [] }
    },
    {
      "gcp.resourceLocations" = {
        enforce        = false
        allowed_values = var.allowed_locations
      }
      # Only identities from this Cloud Identity directory can be granted a
      # role, which also rules out allUsers. public_invoker_projects lifts it
      # per project.
      "iam.allowedPolicyMemberDomains" = {
        enforce        = false
        allowed_values = [data.google_organization.this.directory_customer_id]
      }
    },
  )

  # What the pipeline identity may do, and where: read the app projects (their
  # numbers, for Cloud Run's service agents) and run foundation's Artifact
  # Registry proxy, including its reader grants. Nothing that can create, bind
  # or grant to an identity: app deploy identities and their roles are
  # bootstrap's (main.apps.tf), so nothing CI applies can reach an app's
  # identity or its state.
  pipeline_folder_roles = toset([
    "roles/browser",
    "roles/serviceusage.serviceUsageConsumer",
  ])

  # What each app's deploy identity holds on its own project: enough for its
  # Terraform (Cloud Run service and jobs, Scheduler, secret containers, its
  # runtime service accounts, the store-of-record bucket, alert policies and
  # log metrics) and its `make deploy`. Nothing outside the project, and no
  # project-level IAM: its grants are on its own resources. Its runtime
  # service accounts come from the custom role in main.apps.tf, which has no
  # setIamPolicy, so it can't re-bind any account's trust, its own included.
  # Bucket deletion is denied regardless (main.apps.tf).
  app_deploy_roles = [
    "roles/browser",
    "roles/cloudscheduler.admin",
    "roles/iam.serviceAccountUser",
    "roles/logging.configWriter",
    "roles/monitoring.editor",
    "roles/run.admin",
    "roles/secretmanager.admin",
    "roles/serviceusage.serviceUsageConsumer",
    "roles/storage.admin",
  ]

  # One entry per app and role, keyed "<app>/<role>".
  app_deploy_grants = merge([
    for key, a in var.apps : {
      for role in local.app_deploy_roles : "${key}/${role}" => {
        app  = key
        role = role
      }
    }
  ]...)

  # The projects that hold an app, for the deny policy.
  app_projects = toset([for a in values(var.apps) : a.project])

  pipeline_platform_roles = toset([
    "roles/artifactregistry.admin",
    "roles/browser",
    "roles/serviceusage.serviceUsageConsumer",
  ])
}
