# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo does

Terraform for the jay-withers Google Cloud foundations, the counterpart of
azure-landingzone: org policy, the `apps` folder and projects, the Terraform
state bucket, the GitHub Actions identity pool, this repo's apply identity and
the budget. It's a monorepo with one root module per component under
`terraform/<component>/`, each with its own committed `terraform.tfvars` and
its own state. Today the only component is `bootstrap`. The README covers
the why and the first apply.

## Layout and conventions

- Copied from azure-landingzone: `COMPONENTS` in the Makefile, the
  `check-component` guard, `make test` across every component, and the
  per-component tflint/checkov scripts. Re-copy rather than diverge.
- `scripts/check-tf-standards.sh` is template-repo-terraform-root's, verbatim.
  `locals`/`variable`/`output`/`data` go in matching files, and
  `terraform`/`provider` in `versions.tf`.
- Lock files carry hashes for linux_amd64, linux_arm64 and darwin_arm64
  (`make lock C=<component>`). CI runs amd64, and a missing hash fails
  pre-commit there.
- Tests mock the google provider. Mocks generate random strings, and IAM
  members are validated even against a mock, so a test that applies sets
  realistic `mock_resource` defaults (see `bootstrap/tests`).

## bootstrap: keep these true

- **It is never applied from CI.** Its state is local, by decision, as in
  azure-landingzone. That's why the pipeline identity lives here: no pipeline
  apply can remove or re-scope the identity it runs as. Don't add a backend.
- **The pipeline identity never gets organization-level roles.** Org policy,
  folders, projects and billing stay with a person. Its grants stop at the
  `apps` folder, each app project (only for roles GCP refuses on a folder,
  such as `roles/iam.roleAdmin`), the platform project, and its own
  `gcp-landingzone/` state prefix. It holds no right over the bucket or its IAM. That's why each app's
  state grant (`state_consumers`, by prefix, to the GitHub identity
  directly) is made here by hand. A new grant for it is a decision for the
  user, not a fix for a permission error.
- **The domain restriction (`iam.allowedPolicyMemberDomains`) is lifted per
  project, never for the organization.** A project is exempt only if it's in
  `public_invoker_projects`, because it serves a public Cloud Run service.
- **The platform project is created with gcloud and imported, never created
  by Terraform.** Personal credentials need a quota project before anything
  else can be planned. Resources on the `google.platform` alias, which bills
  calls to that project, also depend on `google_project_service.this`.
  Making projects wait for the org policies creates a cycle.
- **Tests can't import through a mock provider**, so the tests override the
  imported platform project (`override_resource`).
- `deletion_policy = "PREVENT"` on projects, `deletion_protection` on the
  folder, `prevent_destroy` on the state bucket. Don't remove them to make
  a destroy work.

## Not here yet

- `foundation` (applied through cd-terraform) will hold the ghcr.io Artifact
  Registry proxy and each app's deploy identity.
- cd-terraform, schedule-drift and manual-terraform-unlock were removed from
  the template's set, because the shared `terraform-deploy.yml` signs in to
  Azure only. They return once it has a GCP path and github-repos gives this
  repo a main-only `apply` environment with `GCP_*` variables.

## Commit messages

Conventional Commits, enforced by commitlint. `no-commit-to-branch` blocks
direct commits to `main`.

## Repo settings

Managed by jay-withers/github-repos (`var.repos["gcp-landingzone"]`), not
here.
