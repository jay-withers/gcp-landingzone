variable "org_id" {
  type        = string
  description = "Numeric ID of the jaywithers.uk organization (Cloud Identity Free). Console: the project picker, or IAM & Admin -> Settings."

  validation {
    condition     = can(regex("^[0-9]+$", var.org_id))
    error_message = "org_id is the numeric organization ID, not the domain."
  }
}

variable "billing_account" {
  type        = string
  description = "Billing account every project is linked to, and the budget watches."

  validation {
    condition     = can(regex("^[0-9A-F]{6}-[0-9A-F]{6}-[0-9A-F]{6}$", var.billing_account))
    error_message = "billing_account looks like 012345-6789AB-CDEF01."
  }
}

variable "region" {
  type        = string
  description = "The one region anything is created in. europe-west1 because Cloud Run domain mappings exist there and not in europe-west2."
  default     = "europe-west1"
}

variable "allowed_locations" {
  type        = list(string)
  description = "gcp.resourceLocations' allowed values. Global resources (IAM, the identity pool, budgets) are not subject to it."
  default     = ["in:europe-west1-locations"]
}

variable "projects" {
  type = map(object({
    project_id = string
    name       = string
    # Under the `apps` folder, where the pipeline identity's grants stop.
    # Only the platform project sits at the organization root.
    in_apps_folder = optional(bool, true)
    services       = list(string)
  }))
  description = <<-DESCRIPTION
    Projects, keyed by a short name other components use. `platform` is
    required: it holds the state bucket, the identity pool, the pipeline
    identity and (later) the Artifact Registry proxy. One project per app,
    the GCP counterpart of a resource group per app.

    `project_id` is global and permanent: a deleted project holds its ID for
    30 days and it can never be reused after that.
  DESCRIPTION

  validation {
    condition     = contains(keys(var.projects), "platform")
    error_message = "projects must contain a platform entry."
  }

  validation {
    condition     = alltrue([for p in values(var.projects) : can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", p.project_id))])
    error_message = "project_id must be 6-30 lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "public_invoker_projects" {
  type        = set(string)
  description = "Keys of projects exempt from iam.allowedPolicyMemberDomains, so a Cloud Run service there can grant allUsers the invoker role. health's passcode gate is its front door, not IAM."
  default     = []
}

variable "org_policies_to_adopt" {
  type        = set(string)
  description = "Constraints already set on the organization when bootstrap first runs (Google sets several on every new organization), imported rather than created. Check with `gcloud org-policies list --organization=<org_id>`. Empty after the first apply has adopted them."
  default     = []
}

variable "github_owner_id" {
  type        = string
  description = "GitHub's numeric ID for the jay-withers account. The pool trusts tokens from this owner only."
}

variable "pipeline_identity" {
  type = object({
    subject = string
  })
  description = <<-DESCRIPTION
    This repo's CI apply identity (main.pipeline.tf). `subject` is the OIDC
    subject of the `apply` GitHub environment, in the immutable form the repo
    issues: `repo:jay-withers@<owner id>/gcp-landingzone@<repo id>:environment:apply`.
  DESCRIPTION

  validation {
    condition     = can(regex("^repo:[^/]+@[0-9]+/[^/]+@[0-9]+:environment:apply$", var.pipeline_identity.subject))
    error_message = "subject must be the immutable form, for the apply environment."
  }
}

variable "state_consumers" {
  type = map(object({
    subject = string
  }))
  description = <<-DESCRIPTION
    Repos that keep Terraform state in the bucket, keyed by the prefix their
    backend uses (`prefix = "<key>/<env>"`). `subject` is the GitHub
    environment their pipeline plans and applies in, immutable form:
    `repo:jay-withers@<owner id>/<repo>@<repo id>:environment:<env>`.
  DESCRIPTION
  default     = {}

  validation {
    condition     = alltrue([for c in values(var.state_consumers) : can(regex("^repo:[^/]+@[0-9]+/[^/]+@[0-9]+:environment:[^:]+$", c.subject))])
    error_message = "Each subject must be the immutable repo:<owner>@<id>/<repo>@<id>:environment:<env> form."
  }

  validation {
    condition     = !contains(keys(var.state_consumers), "gcp-landingzone")
    error_message = "gcp-landingzone's own prefix is its apply identity's (main.pipeline.tf)."
  }
}

variable "state_bucket_name" {
  type        = string
  description = "The Terraform state bucket. Bucket names are global."
}

variable "budget_amount" {
  type        = number
  description = "Monthly budget, in the billing account's own currency. Alerts at 50% and 100% of actual spend, and at 100% forecast."
  default     = 5

  validation {
    # The API's `units` is an integer; a fraction would need `nanos`.
    condition     = var.budget_amount > 0 && floor(var.budget_amount) == var.budget_amount
    error_message = "budget_amount must be a whole number above zero."
  }
}

variable "labels" {
  type        = map(string)
  description = "Extra labels merged onto every labelled resource."
  default     = {}
}
