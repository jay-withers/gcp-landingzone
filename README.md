# gcp-landingzone

Terraform for the jay-withers Google Cloud foundations: the counterpart of
[azure-landingzone](https://github.com/jay-withers/azure-landingzone). It
holds the organization's guardrails, the projects, the Terraform state bucket,
and the identity pool GitHub Actions signs in through. health is the first app
here, on Cloud Run in europe-west1.

One component per concern, each its own root module with its own state.
`bootstrap` is applied by hand. Later components will plan on merge and apply
through `cd-terraform`, once the shared workflows can sign in to GCP.

## Components

| Component | Owns | Standing cost |
| --------- | ---- | ------------- |
| [`bootstrap`](terraform/bootstrap/) | Org policies, the `apps` folder, the `platform` and app projects with their APIs, the state bucket, the GitHub identity pool, this repo's apply identity, the monthly budget. Its own state is local | cents/month |

## Organization

```text
jaywithers.uk (organization, Cloud Identity Free)
├── jaywithers-platform     state bucket, identity pool, apply identity
└── apps/                   the apply identity's grants stop here
    └── jaywithers-health-dev
```

**Org policy is the guardrail, as Azure Policy is there:**
- Nothing outside europe-west1.
- No service account keys.
- No public buckets or per-object ACLs.
- No default networks.
- No default-service-account Editor grants.
- Only this directory's identities can be granted roles.

health's project is the one exception to that last rule, so its Cloud Run
service can be public behind its passcode gate.

## Cost

Expected under $1/month across the whole estate on GCP:
- Projects, IAM, the pool, org policy and the budget are free.
- The state bucket is a few KB.
- The ghcr.io proxy, when foundation adds it, is cents.

There is no credit, unlike Azure's $150, so the budget (5 a month, in the
billing account's currency) emails at 50%, at 100%, and when the month is
forecast to pass 100%.

## First apply (by hand)

You need:
- an organization administrator on jaywithers.uk, who also holds Organization
  Policy Administrator on the organization
- Billing Account Administrator on the billing account, since creating the
  budget needs more than Billing Account User
- the Google Cloud CLI

Personal credentials need a quota project, and the platform project is the
only sensible one, so create it with gcloud first. Bootstrap then adopts it.

```bash
ORG=<org id>
gcloud auth login
gcloud projects create jaywithers-platform --organization="$ORG" --name=platform
gcloud billing projects link jaywithers-platform --billing-account=01B172-6360A2-5D15E2
gcloud services enable --project=jaywithers-platform \
  cloudresourcemanager.googleapis.com serviceusage.googleapis.com \
  cloudbilling.googleapis.com orgpolicy.googleapis.com \
  billingbudgets.googleapis.com iam.googleapis.com storage.googleapis.com
gcloud auth application-default login
gcloud auth application-default set-quota-project jaywithers-platform

# What Google already set on the new organization: these go in
# org_policies_to_adopt, and the org id goes in org_id
# (terraform/bootstrap/terraform.tfvars).
gcloud org-policies list --organization="$ORG"

make apply C=bootstrap
```

Then empty `org_policies_to_adopt`, since those policies are in state now. A
second `make plan C=bootstrap` should show no changes.

## Commands

```bash
make install            # mise tools and pre-commit hooks
make lint               # every pre-commit hook against every file
make test               # terraform test, mocked providers, no Google auth
make plan C=bootstrap   # needs application default credentials
make apply C=bootstrap
make lock C=bootstrap   # provider lock for linux amd64/arm64 and macOS arm64
```
