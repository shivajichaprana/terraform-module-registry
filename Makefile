# Local entry points for the module registry.
#
# Every target mirrors the flags used by the pipeline in .github/workflows/ci.yml,
# so a green `make ci` locally means a green pipeline run.

SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

# Discovered from the tree so a new module or example is picked up automatically.
MODULE_DIRS  := $(patsubst %/,%,$(dir $(wildcard modules/*/main.tf)))
MODULES      := $(notdir $(MODULE_DIRS))
EXAMPLE_DIRS := $(patsubst %/,%,$(dir $(wildcard modules/*/examples/*/main.tf)))
TF_DIRS      := $(MODULE_DIRS) $(EXAMPLE_DIRS)
TEST_DIR     := tests

TERRAFORM_DOCS_FORMAT := markdown table

.PHONY: help init fmt fmt-check validate lint scan test docs docs-check \
        manifest manifest-check commitlint release-dry release ci clean

help: ## Show available targets
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

init: ## Initialize every module, example, and the test harness (no backend)
	@for dir in $(TF_DIRS) $(TEST_DIR); do \
		echo "==> init $$dir"; \
		terraform -chdir=$$dir init -backend=false -input=false; \
	done

fmt: ## Rewrite all configuration into canonical format
	terraform fmt -recursive

fmt-check: ## Check formatting without writing (pipeline gate)
	terraform fmt -check -diff -recursive

validate: ## Initialize and validate every module and example
	@for dir in $(TF_DIRS); do \
		echo "==> validate $$dir"; \
		terraform -chdir=$$dir init -backend=false -input=false; \
		terraform -chdir=$$dir validate; \
	done

lint: ## Run tflint across every module
	@export TFLINT_CONFIG_FILE="$(ROOT_DIR)/.tflint.hcl"; \
	tflint --init; \
	for module in $(MODULES); do \
		echo "==> tflint modules/$$module"; \
		tflint --chdir=modules/$$module --minimum-failure-severity=error; \
	done

scan: ## Run the Checkov security policy scan
	checkov --config-file .checkov.yaml

test: ## Run the native Terraform tests (offline, mocked provider)
	terraform -chdir=$(TEST_DIR) init -backend=false -input=false
	terraform -chdir=$(TEST_DIR) test

docs: ## Render module documentation with terraform-docs
	@for module in $(MODULES); do \
		echo "==> terraform-docs modules/$$module"; \
		terraform-docs $(TERRAFORM_DOCS_FORMAT) modules/$$module; \
	done

docs-check: docs manifest-check ## Verify docs render and the manifest is current

manifest: ## Regenerate registry.json from the module sources
	python3 scripts/generate_manifest.py --write

manifest-check: ## Fail if registry.json has drifted from the sources
	python3 scripts/generate_manifest.py --check

commitlint: ## Validate the most recent commit message
	npm run commitlint

release-dry: ## Preview the next release without publishing anything
	npm run release:dry

release: ## Cut a release: version, changelog, manifest, tag
	npm run release

ci: fmt-check validate lint scan test docs-check ## Run every quality gate in pipeline order
	@echo "All quality gates passed."

clean: ## Remove local Terraform and Node state
	find . -type d -name '.terraform' -prune -exec rm -rf {} +
	find . -type f -name '.terraform.lock.hcl' -delete
	find . -type f -name 'terraform.tfstate*' -delete
	rm -rf node_modules
	find . -type d -name '__pycache__' -prune -exec rm -rf {} +
