# terraform-module-registry

A private library of hardened, reusable Terraform modules. Each module ships
**secure defaults** so that a minimal call produces a well-configured, locked-down
resource — no extra flags required to be safe.

## Design principles

- **Secure by default** — encryption, least privilege, and public-access blocking are on unless a caller explicitly opts out.
- **Small, composable modules** — one responsibility per module; compose them, don't fork them.
- **Input validation** — variables carry `validation` blocks so misconfiguration fails at plan time, not in production.
- **Documented contract** — every module has a README with an inputs/outputs table and runnable examples under `examples/`.
- **Versioned releases** — pin consumers to an immutable tag (`?ref=v1.0.0`), never `main`.

## Repository layout

| Path | Purpose |
|------|---------|
| `registry.json` | Machine-readable index of published modules. |
| `modules/<name>/` | A module: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, `README.md`. |
| `modules/<name>/examples/` | Runnable example configurations. |
| `tests/` | Native Terraform test harness (`*.tftest.hcl`) run against a mocked provider. |
| `.tflint.hcl` | tflint configuration for language and AWS linting. |
| `.checkov.yaml` | Checkov policy-scan configuration. |
| `scripts/generate_manifest.py` | Generates `registry.json` from the module sources. |
| `.releaserc.json`, `.commitlintrc.json`, `package.json` | Release automation and commit-message linting. |
| `CHANGELOG.md` | Generated release history. |
| `LICENSE` | MIT license. |

## Modules

| Module | Summary | Status |
|--------|---------|--------|
| [`s3-bucket`](./modules/s3-bucket) | Hardened S3 bucket with encryption, public-access blocking, and TLS enforcement. | stable |
| [`vpc`](./modules/vpc) | Multi-AZ VPC with public/private subnets, NAT egress, and encrypted VPC Flow Logs. | stable |
| [`iam-role`](./modules/iam-role) | Reusable IAM role with service/account/OIDC trust, policies, and a permissions boundary. | stable |

## Consuming a module

Reference a module by its subdirectory and pin an immutable release tag:

```hcl
module "logs" {
  source = "github.com/<your-github-org>/terraform-module-registry//modules/s3-bucket?ref=v1.0.0"

  bucket_name = "example-app-logs"
}
```

Placeholders in examples — `<your-github-org>`, account id `123456789012`, and
`arn:aws:kms:...:123456789012:key/<key-id>` — are illustrative; substitute your
own values.

## Testing and quality gates

Every module is covered by native Terraform tests under [`tests/`](./tests).
They run with `command = plan` against a `mock_provider "aws"`, so the whole
suite executes offline — no credentials and no resources created. Positive runs
assert on plan-known values (outputs, configuration arguments, resource counts);
negative runs use `expect_failures` to confirm the input validations reject bad
configuration.

Two static scanners back the tests: `tflint` (language hygiene plus AWS resource
rules, configured in `.tflint.hcl`) and `checkov` (security policy scan,
configured in `.checkov.yaml`).

```bash
# Native tests
cd tests && terraform init -backend=false && terraform test

# Static analysis (from the repository root)
tflint --chdir=modules/s3-bucket
checkov --config-file .checkov.yaml
```

## Releasing and versioning

The registry is versioned as a whole and consumers pin an immutable tag (`?ref=v1.0.0`), never `main`. Releases are automated from [Conventional Commit](https://www.conventionalcommits.org/) messages: the commit history determines the next [Semantic Version](https://semver.org/), the changelog and module manifest are regenerated, and a tag and release are published.

`registry.json` is never edited by hand — it is generated from the module sources by `scripts/generate_manifest.py`, which parses each module's providers, minimum Terraform version, inputs, outputs, and examples.

```bash
# Regenerate the manifest after changing a module
npm run manifest          # python3 scripts/generate_manifest.py --write

# Verify the committed manifest matches the sources
npm run manifest:check    # python3 scripts/generate_manifest.py --check
```

See [RELEASING.md](./RELEASING.md) for the version-bump rules and the full release flow.

## Contributing a module

1. Create `modules/<name>/` with `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, and a `README.md`.
2. Add secure defaults and `validation` blocks to every input that can be misused.
3. Provide at least a `basic` example under `examples/`.
4. Register the module in `registry.json`.
5. Add native tests under `tests/<name>.tftest.hcl` covering the secure defaults and the input validations.
6. Run `terraform fmt`, `terraform validate`, and `terraform test` before opening a pull request.

## License

MIT — see [LICENSE](./LICENSE).
