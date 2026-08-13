# Test harness

Native Terraform tests for every published module, plus the entry point the
quality gates run from.

## What lives here

| File | Purpose |
|------|---------|
| `versions.tf` | Minimal root configuration so `terraform test` can initialize the AWS provider schema. |
| `s3_bucket.tftest.hcl` | Unit tests for `modules/s3-bucket`. |
| `vpc.tftest.hcl` | Unit tests for `modules/vpc`. |
| `iam_role.tftest.hcl` | Unit tests for `modules/iam-role`. |
| `examples.tftest.hcl` | Contract tests that replay every published example. |

## How the tests work

Each test file declares a `mock_provider "aws"`, so runs execute entirely
offline — no credentials, no AWS API calls, nothing created. Every `run` block
uses `command = plan` and pulls the module under test in via
`module { source = "../modules/<name>" }`.

Assertions only reference values that are known at plan time:

- module **outputs** that derive from locals (for example `sse_algorithm`),
- **configuration arguments** set from inputs (for example a CIDR block or a
  retention period),
- resource **counts** driven by inputs (for example the number of NAT gateways).

Provider-computed attributes (ARNs, IDs, rendered policy JSON) are deliberately
never asserted, because a mocked provider does not produce their real values.

Negative runs use `expect_failures` to prove that the input `validation` blocks
and lifecycle `precondition`s reject bad configuration at plan time.

## Running the tests

From this directory:

```bash
terraform init -backend=false
terraform test
```

Or, from the repository root, run everything the CI quality gates run:

```bash
make test    # native tests
make lint    # tflint
make scan    # checkov policy scan
```

## Known limitation

The `vpc` module's subnet-count `precondition`s (more subnet CIDRs than
availability zones) are shadowed by an index-out-of-range error in the subnet
`for_each` that surfaces first, so they are not exercised by a dedicated
negative run; the equivalent misconfiguration is instead caught earlier by the
per-CIDR input `validation`.
