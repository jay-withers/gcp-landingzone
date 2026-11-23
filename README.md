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

## Manual steps

Everything below is done by a person, once, in this order. It's the runbook
for doing it again, and the record of how the current organization was set up
on 2026-11-22 and 23. Nothing here is automated, because each step either
creates the identity automation would run as or needs rights no pipeline
holds.

### 1. The organization

GCP organizations come from a Cloud Identity directory. A personal Gmail
account has none, and without an organization there is no org policy.

1. Sign up for **Cloud Identity Free** at
   <https://workspace.google.com/gcpidentity/signup> with `jaywithers.uk`.
   This creates an admin user on the domain.
2. Verify the domain with the `google-site-verification=…` TXT record on the
   apex that the sign-up shows. The same record also verifies the domain
   for Search Console, which Cloud Run domain mappings need later.
3. Note the organization ID (`gcloud organizations list`; here
   `668995077740`) and the billing account (here `01B172-6360A2-5D15E2`).
   Both go in `terraform/bootstrap/terraform.tfvars` as `org_id` and
   `billing_account`, along with the other tenant-bound literals there:
   project IDs, the bucket name, and the GitHub IDs.

### 2. Roles for whoever applies bootstrap

Organization Administrator manages IAM on the organization, but doesn't
include creating folders or setting org policy. (Here this step came after a
first apply failed on the folder: Project Creator was already held through
the domain-wide default grant every new organization has.)

```bash
gcloud auth login
ORG=668995077740
ME=$(gcloud config get-value account)
for role in roles/resourcemanager.folderAdmin \
            roles/resourcemanager.projectCreator \
            roles/orgpolicy.policyAdmin; do
  gcloud organizations add-iam-policy-binding "$ORG" \
    --member="user:$ME" --role="$role" --condition=None
done
# The budget needs more than Billing Account User. Run as whichever account
# owns the billing account.
gcloud billing accounts add-iam-policy-binding 01B172-6360A2-5D15E2 \
  --member="user:$ME" --role=roles/billing.admin
```

### 3. The platform project and a quota project

Personal credentials need a quota project before Terraform can plan anything,
and none exists yet. So the platform project is created with gcloud, and
bootstrap imports it.

```bash
ORG=668995077740
gcloud projects create jaywithers-platform --organization="$ORG" --name=platform
gcloud billing projects link jaywithers-platform --billing-account=01B172-6360A2-5D15E2
gcloud services enable --project=jaywithers-platform \
  cloudresourcemanager.googleapis.com serviceusage.googleapis.com \
  cloudbilling.googleapis.com orgpolicy.googleapis.com \
  billingbudgets.googleapis.com iam.googleapis.com storage.googleapis.com
gcloud auth application-default login
gcloud auth application-default set-quota-project jaywithers-platform
```

### 4. The policies Google already set

```bash
gcloud org-policies list --organization=668995077740
```

Every constraint bootstrap manages that appears there goes in
`org_policies_to_adopt` in `terraform/bootstrap/terraform.tfvars`, under the
exact name listed. Some are managed constraints (`iam.managed.*`). A name
bootstrap doesn't manage fails validation at plan time.

### 5. Apply bootstrap, from a clone of your own

Bootstrap's state is local, so apply it from a clone you keep, not from
factory's `repos/` mirror:

```bash
git clone https://github.com/jay-withers/gcp-landingzone.git ~/git/gcp-landingzone
cd ~/git/gcp-landingzone
make apply C=bootstrap
```

Keep a copy of `terraform/bootstrap/terraform.tfstate` outside the machine,
and refresh it after every bootstrap apply. Every name in it is
deterministic, so a lost copy means `terraform import`, but a copy saves
that.

### 6. After the first apply

Empty `org_policies_to_adopt` (those policies are in state now) in a PR. A
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
