# bootstrap

Everything the rest of GCP stands on. Apply it first, by hand, as an
organization administrator. Nothing else can `init` until its state bucket
exists, and no pipeline can sign in until its identity pool does.

- **Org policy** (`main.policy.tf`): the guardrails, plus the per-project
  exemption from the domain restriction for projects with a public Cloud Run
  service. The pipeline identity never holds Org Policy Administrator, so
  these change only here.
- **Folder and projects** (`main.tf`): `jaywithers-platform` at the root, app
  projects in `apps/`. Each is linked to billing, gets its APIs, has no default
  network, and has `deletion_policy = "PREVENT"`.
- **State** (`main.state.tf`): `jaywithers-tfstate`, versioned, with 30-day
  soft delete and `prevent_destroy`. One prefix per repo, as follows:
  - Each app in `apps` gets object access under its own prefix, granted to
    its deploy identity.
  - Listing object names is bucket-wide, because GCS checks list against the
    bucket.
  - The pipeline identity gets `gcp-landingzone/` and no rights over the
    bucket or its IAM.
- **Identity federation** (`main.identity-federation.tf`): pool `github`, with
  provider `github-actions` accepting jay-withers tokens only.
- **Pipeline identity** (`main.pipeline.tf`): `gcp-landingzone-apply`, bound to
  this repo's `apply` environment. Its roles are limited to the `apps` folder,
  the platform project and the state bucket.
- **App deploy identities** (`main.apps.tf`): for each entry in `apps`, a
  `<app>-deploy` service account in its project, bound to its repo's GitHub
  environment alone, with the roles its Terraform and deploy need on that
  project (`local.app_deploy_roles`) and its state prefix. Plus a deny policy
  on each app project that stops anyone deleting a bucket there: the store
  of record's lock.
- **Budget** (`main.budget.tf`).

Its own state is in the bucket it creates, under `bootstrap/`, where the
pipeline identity's prefix grant doesn't reach. The bucket's `prevent_destroy`
and 30-day soft delete stand in for azure-landingzone's choice of local state.
A fresh organization applies locally first, then migrates (the README's
"Manual steps"). Every name is a literal in `terraform.tfvars`, so even lost
state is recovered with `terraform import`.

**If a bootstrap apply ever cuts off your access to the bucket** (an org
policy or IAM change gone wrong), bootstrap can't read the state it needs to
undo it. Fix the access by hand first (`gcloud storage buckets
add-iam-policy-binding`, or `gcloud org-policies` for the policy), then plan
again. A state write that went wrong is recoverable from the bucket's object
versions (`gcloud storage ls -a gs://jaywithers-tfstate/bootstrap/`).

## Traps

- **New organizations come with policies already set.** Google applies its
  "secure by default" policies to every organization made since 2024.
  Creating one that exists fails, so the first apply imports them: list them
  in `org_policies_to_adopt`, from
  `gcloud org-policies list --organization=<org id>`.
- **Some of those are managed constraints (`iam.managed.*`), not the legacy
  ones with the same rule.** Manage the name the list shows. Adding the
  legacy constraint beside a managed one creates a second policy for one
  rule rather than adopting the first.
- **Personal credentials need a quota project, and nothing exists to be
  one.** Org Policy, Billing Budgets, IAM and Service Usage refuse calls from
  application default credentials that name none. So the platform project is
  created with gcloud first (the README's steps) and imported by `main.tf`'s
  unconditional import block, which does nothing once it's in state. The
  `google.platform` alias then bills every later call to that project
  explicitly.
- **IDs outlive deletes.** A project ID is never reusable. A pool, provider or
  custom role holds its ID for 7-30 days after deletion. Renaming any of them
  is a wait, not an apply.
- **`gcp.resourceLocations` blocks multi-region and global-replication
  defaults.** Secret Manager's automatic replication is one of them, so
  secrets need user-managed replication in europe-west1.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 8.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_google"></a> [google](#provider\_google) | ~> 8.0 |
| <a name="provider_google.platform"></a> [google.platform](#provider\_google.platform) | ~> 8.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [google_billing_budget.monthly](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/billing_budget) | resource |
| [google_folder.apps](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/folder) | resource |
| [google_folder_iam_member.pipeline](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/folder_iam_member) | resource |
| [google_iam_deny_policy.no_bucket_delete](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/iam_deny_policy) | resource |
| [google_iam_workload_identity_pool.github](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/iam_workload_identity_pool) | resource |
| [google_iam_workload_identity_pool_provider.github](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/iam_workload_identity_pool_provider) | resource |
| [google_org_policy_policy.org](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/org_policy_policy) | resource |
| [google_org_policy_policy.public_invoker](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/org_policy_policy) | resource |
| [google_project.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project) | resource |
| [google_project_iam_member.app_deploy](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_project_iam_member.pipeline_apps](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_project_iam_member.pipeline_platform](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_project_service.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_service) | resource |
| [google_service_account.app_deploy](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_service_account.pipeline](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_service_account_iam_member.app_deploy_federation](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account_iam_member) | resource |
| [google_service_account_iam_member.pipeline_federation](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account_iam_member) | resource |
| [google_storage_bucket.tfstate](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket) | resource |
| [google_storage_bucket_iam_member.consumer_state](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket_iam_member) | resource |
| [google_storage_bucket_iam_member.consumer_state_list](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket_iam_member) | resource |
| [google_storage_bucket_iam_member.pipeline_state](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket_iam_member) | resource |
| [google_storage_bucket_iam_member.pipeline_state_list](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket_iam_member) | resource |
| [google_organization.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/organization) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_allowed_locations"></a> [allowed\_locations](#input\_allowed\_locations) | gcp.resourceLocations' allowed values. Global resources (IAM, the identity pool, budgets) are not subject to it. | `list(string)` | <pre>[<br/>  "in:europe-west1-locations"<br/>]</pre> | no |
| <a name="input_apps"></a> [apps](#input\_apps) | Each app deployed from its own repo's pipeline, keyed by the app's name,<br/>which is also its state prefix (`prefix = "<key>/<env>"` in its gcs<br/>backend). `project` is its key in var.projects (an app project, in the<br/>apps folder). `subject` is the GitHub environment its pipeline plans,<br/>applies and deploys in, immutable form:<br/>`repo:jay-withers@<owner id>/<repo>@<repo id>:environment:<env>`.<br/><br/>Each gets a `<key>-deploy` service account in its project, federated to<br/>that subject alone, holding local.app\_deploy\_roles on the project and its<br/>state prefix; and its project gets the deny policy against bucket<br/>deletion (main.apps.tf). | <pre>map(object({<br/>    project = string<br/>    subject = string<br/>  }))</pre> | `{}` | no |
| <a name="input_billing_account"></a> [billing\_account](#input\_billing\_account) | Billing account every project is linked to, and the budget watches. | `string` | n/a | yes |
| <a name="input_budget_amount"></a> [budget\_amount](#input\_budget\_amount) | Monthly budget, in the billing account's own currency. Alerts at 50% and 100% of actual spend, and at 100% forecast. | `number` | `5` | no |
| <a name="input_github_owner_id"></a> [github\_owner\_id](#input\_github\_owner\_id) | GitHub's numeric ID for the jay-withers account. The pool trusts tokens from this owner only. | `string` | n/a | yes |
| <a name="input_labels"></a> [labels](#input\_labels) | Extra labels merged onto every labelled resource. | `map(string)` | `{}` | no |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | Numeric ID of the jaywithers.uk organization (Cloud Identity Free). Console: the project picker, or IAM & Admin -> Settings. | `string` | n/a | yes |
| <a name="input_org_policies_to_adopt"></a> [org\_policies\_to\_adopt](#input\_org\_policies\_to\_adopt) | Constraints already set on the organization when bootstrap first runs (Google sets several on every new organization), imported rather than created. Check with `gcloud org-policies list --organization=<org_id>`. Empty after the first apply has adopted them. | `set(string)` | `[]` | no |
| <a name="input_pipeline_identity"></a> [pipeline\_identity](#input\_pipeline\_identity) | This repo's CI apply identity (main.pipeline.tf). `subject` is the OIDC<br/>subject of the `apply` GitHub environment, in the immutable form the repo<br/>issues: `repo:jay-withers@<owner id>/gcp-landingzone@<repo id>:environment:apply`. | <pre>object({<br/>    subject = string<br/>  })</pre> | n/a | yes |
| <a name="input_projects"></a> [projects](#input\_projects) | Projects, keyed by a short name other components use. `platform` is<br/>required: it holds the state bucket, the identity pool, the pipeline<br/>identity and (later) the Artifact Registry proxy. One project per app,<br/>the GCP counterpart of a resource group per app.<br/><br/>`project_id` is global and permanent: a deleted project holds its ID for<br/>30 days and it can never be reused after that. | <pre>map(object({<br/>    project_id = string<br/>    name       = string<br/>    # Under the `apps` folder, where the pipeline identity's grants stop.<br/>    # Only the platform project sits at the organization root.<br/>    in_apps_folder = optional(bool, true)<br/>    services       = list(string)<br/>  }))</pre> | n/a | yes |
| <a name="input_public_invoker_projects"></a> [public\_invoker\_projects](#input\_public\_invoker\_projects) | Keys of projects exempt from iam.allowedPolicyMemberDomains, so a Cloud Run service there can grant allUsers the invoker role. health's passcode gate is its front door, not IAM. | `set(string)` | `[]` | no |
| <a name="input_region"></a> [region](#input\_region) | The one region anything is created in. europe-west1 because Cloud Run domain mappings exist there and not in europe-west2. | `string` | `"europe-west1"` | no |
| <a name="input_state_bucket_name"></a> [state\_bucket\_name](#input\_state\_bucket\_name) | The Terraform state bucket. Bucket names are global. Also written as a literal in versions.tf's backend block, which can't read variables: change both together. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_app_deploy_service_accounts"></a> [app\_deploy\_service\_accounts](#output\_app\_deploy\_service\_accounts) | Each app's deploy identity, for GCP\_SERVICE\_ACCOUNT on its GitHub environment (github-repos), and to add as a Search Console owner of a custom domain. |
| <a name="output_apps_folder"></a> [apps\_folder](#output\_apps\_folder) | The apps folder (`folders/<id>`), where the pipeline identity's grants stop. |
| <a name="output_org_id"></a> [org\_id](#output\_org\_id) | The organization's numeric ID. |
| <a name="output_pipeline_service_account"></a> [pipeline\_service\_account](#output\_pipeline\_service\_account) | This repo's apply identity (GCP\_SERVICE\_ACCOUNT on its `apply` environment). |
| <a name="output_projects"></a> [projects](#output\_projects) | Each project's ID and number, keyed as in var.projects. |
| <a name="output_state_bucket"></a> [state\_bucket](#output\_state\_bucket) | The Terraform state bucket, for every gcs backend's `bucket`. |
| <a name="output_workload_identity_pool"></a> [workload\_identity\_pool](#output\_workload\_identity\_pool) | The pool's full name, for `principal://iam.googleapis.com/<this>/subject/<subject>` bindings. |
| <a name="output_workload_identity_provider"></a> [workload\_identity\_provider](#output\_workload\_identity\_provider) | The full provider name google-github-actions/auth takes as `workload_identity_provider` (github-repos sets it as GCP\_WORKLOAD\_IDENTITY\_PROVIDER). |
<!-- END_TF_DOCS -->
