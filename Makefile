# Apply order, and nothing enforces it. bootstrap first: it creates the state
# bucket everyone's state is in (its own under bootstrap/), the identity pool
# and the pipeline identity. Later components are listed after it as they arrive.
COMPONENTS := bootstrap

# Component selector. Every terraform target needs it (test excepted, see below):
#
#   make plan C=bootstrap
#
C      ?=
TF_DIR := terraform
DIR    := $(TF_DIR)/$(C)

.DEFAULT_GOAL := help

.PHONY: help install lint fmt check-component init validate plan apply destroy test validate-all lock

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'
	@printf "\nComponents (apply in this order): %s\n" "$(COMPONENTS)"
	@printf "Every terraform target needs C=<component>, except test (default: every component).\n"

install: ## Install mise tools and pre-commit hooks (run once after cloning)
	mise install
	pre-commit install
	pre-commit install --hook-type commit-msg

lint: ## Run all pre-commit hooks against every file
	pre-commit run --all-files

fmt: ## terraform fmt -recursive across every component
	terraform fmt -recursive $(TF_DIR)/

# Guard rather than defaulting to a component: applying the wrong one by
# accident is worse than being told to name it.
check-component:
	@test -n "$(C)" || { echo "set C=<component>, one of: $(COMPONENTS)"; exit 1; }
	@echo "$(COMPONENTS)" | tr ' ' '\n' | grep -qx "$(C)" \
		|| { echo "not a component: $(C) (one of: $(COMPONENTS))"; exit 1; }

init: check-component ## terraform init
	terraform -chdir=$(DIR) init

validate: init ## terraform init + validate
	terraform -chdir=$(DIR) validate

plan: init ## terraform plan (pass extra flags with TFARGS=...)
	terraform -chdir=$(DIR) plan $(TFARGS)

apply: init ## terraform apply (pass extra flags with TFARGS=...)
	terraform -chdir=$(DIR) apply $(TFARGS)

destroy: init ## terraform destroy
	terraform -chdir=$(DIR) destroy $(TFARGS)

# Every platform that runs Terraform here: CI (amd64), and arm64 Linux and
# macOS machines. A lock missing CI's hash fails pre-commit on every PR.
lock: check-component ## Refresh a component's provider lock for every platform
	terraform -chdir=$(DIR) providers lock \
		-platform=linux_amd64 -platform=linux_arm64 -platform=darwin_arm64

# Unlike the other terraform targets, C= is optional here and init skips the
# backend: terraform test runs against mocked providers, so it needs neither
# Google credentials nor state. With no C it covers every component, which is
# what lets factory's verify.sh (a bare `make test`) pass. A component with no
# tests/*.tftest.hcl is reported and skipped, not failed.
test: ## terraform test, mocked providers, no Google auth (C=<component> for one; default every component)
	@$(if $(C),$(MAKE) --no-print-directory check-component C=$(C) &&) \
	for c in $(or $(C),$(COMPONENTS)); do \
		if ! ls $(TF_DIR)/$$c/tests/*.tftest.hcl >/dev/null 2>&1; then \
			echo "==> $$c: no tests"; continue; \
		fi; \
		echo "==> $$c"; \
		terraform -chdir=$(TF_DIR)/$$c init -backend=false >/dev/null || exit 1; \
		terraform -chdir=$(TF_DIR)/$$c test || exit 1; \
	done

validate-all: ## init + validate every component
	@for c in $(COMPONENTS); do \
		echo "==> $$c"; \
		terraform -chdir=$(TF_DIR)/$$c init -backend=false >/dev/null || exit 1; \
		terraform -chdir=$(TF_DIR)/$$c validate || exit 1; \
	done
