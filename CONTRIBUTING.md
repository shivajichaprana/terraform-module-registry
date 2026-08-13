# Contributing

Thanks for improving the registry. Every module here is consumed by pinned
reference from other configurations, so the bar is a stable, documented,
secure-by-default contract rather than a working `apply`.

## Prerequisites

| Tool | Version | Used for |
|------|---------|----------|
| Terraform | `>= 1.6` (CI pins `1.9.8`) | fmt, validate, native tests |
| Python | `>= 3.9` | manifest generation (standard library only) |
| tflint | `v0.53.0` | language and AWS resource linting |
| Checkov | `>= 3, < 4` | security policy scan |
| terraform-docs | `v0.19.0` | rendering module documentation |
| Node.js | `>= 20` | commitlint and release automation (optional locally) |

`make help` lists every target. `make ci` runs the full gate set with the same
flags as the pipeline, so a green local run means a green pipeline run.

## Module conventions

A module lives in `modules/<name>/` and always contains:

```
modules/<name>/
├── main.tf          # resources and locals
├── variables.tf     # inputs, with validation on anything misusable
├── outputs.tf       # the module's public contract
├── versions.tf      # required_version and required_providers
├── README.md        # security posture, usage, inputs/outputs tables, examples
└── examples/
    ├── basic/       # minimal call — required inputs only
    └── complete/    # the interesting options exercised together
```

Hold to these rules:

1. **Secure defaults.** A call that passes only the required inputs must be safe:
   encryption on, public access blocked, least privilege, logging where it is
   cheap. If a caller wants something less safe, they opt out explicitly.
2. **Validate inputs.** Anything that can be typo'd or misused gets a `validation`
   block — name patterns, enums, ARNs, numeric ranges. Rules that span inputs go
   in a `lifecycle.precondition` on the resource they constrain.
3. **Fail at plan time.** A misconfiguration should never reach apply. Prefer a
   precondition over a runtime surprise.
4. **One responsibility.** If a module starts growing a second purpose, split it
   and compose the two.
5. **No hidden dependencies.** Modules do not nest other registry modules; callers
   compose them by passing outputs between calls.
6. **Placeholders only.** Examples and docs use `<your-github-org>`, account id
   `123456789012`, and `example-` resource names. Never commit a real account id,
   ARN, bucket name, or any credential.
7. **Tag everything.** Accept a `tags` map and apply it to every resource that
   supports tagging.

## Adding a module

1. Create `modules/<name>/` with the layout above.
2. Write `variables.tf` first — the inputs are the contract; add `validation` as
   you go.
3. Implement `main.tf` with secure defaults, and expose the identifiers a consumer
   will actually need in `outputs.tf`.
4. Add `examples/basic` (required inputs only) and, when the module has meaningful
   options, `examples/complete`.
5. Write the module `README.md`: security posture, usage snippets, inputs table,
   outputs table, and links to the examples.
6. Add `tests/<name>.tftest.hcl` — see [Testing](#testing).
7. Extend `tests/examples.tftest.hcl` with a contract run per new example.
8. Regenerate the index: `make manifest`. Set the module's `summary` and `status`
   in `registry.json` (those two fields are curated and preserved on regeneration).
9. Add a row to the catalog table in `README.md` and a section in
   `docs/module-catalog.md`.
10. Run `make ci`.

## Changing an existing module

- Adding an optional input with a safe default is a **minor** change.
- Fixing behaviour without altering the contract is a **patch**.
- Removing or renaming an input or output, or changing a default in a way that
  would modify existing infrastructure on the next apply, is a **major** change:
  flag it with `!` or a `BREAKING CHANGE:` footer so consumers are not surprised.

Update the module README, the catalog entry, and the tests in the same change.
Run `make manifest` afterwards — the manifest carries a content hash, so a source
change without a regenerated manifest fails the docs gate.

## Testing

Tests live at the repository root under `tests/` and run offline:

- Each file declares `mock_provider "aws"`, so there are no credentials, no API
  calls, and nothing created.
- Every `run` uses `command = plan` and pulls the module in via
  `module { source = "../modules/<name>" }`.
- Assertions reference only plan-known values: outputs derived from locals,
  configuration arguments set from inputs, and resource counts. Provider-computed
  attributes (ARNs, IDs, rendered policy JSON) are never asserted, because a mocked
  provider does not produce their real values.
- Negative runs use `expect_failures` to prove the validations and preconditions
  reject bad configuration.

Cover at minimum:

| Case | Why |
|------|-----|
| Secure defaults | The bare call really is safe — this is the module's core promise. |
| Each meaningful toggle | Opting in or out changes the plan the way the README claims. |
| Every input `validation` | A bad value is rejected at plan time, not silently accepted. |
| Each published example | `tests/examples.tftest.hcl` replays the example and asserts what it advertises. |

```bash
make test          # native module and example-contract tests
make lint          # tflint
make scan          # checkov
```

## Documentation

Module documentation is written by hand and checked by `terraform-docs` in CI, so
inputs and outputs tables must stay in step with the code. `registry.json` is
generated — never edit it by hand; run `make manifest` and commit the result.

## Commit messages

Commits follow [Conventional Commits](https://www.conventionalcommits.org/) and
are validated by commitlint (`.commitlintrc.json`). The type determines the next
release version:

| Type | Bump |
|------|------|
| `fix:`, `perf:`, `refactor:`, `revert:` | patch |
| `feat:` | minor |
| any type with `!` or a `BREAKING CHANGE:` footer | major |
| `build:`, `ci:`, `test:`, `chore:`, `docs:` | no release |

```
feat(modules): add cloudfront distribution module with logging enabled
fix(vpc): associate the shared private route table in every zone
feat(iam-role)!: drop the deprecated trusted_principals input
```

Scopes are kebab-case and the header stays within 100 characters. Validate your
latest commit with `npm run commitlint`.

## Pull request checklist

- [ ] `make ci` passes locally.
- [ ] Secure defaults hold for a call that passes only required inputs.
- [ ] Every misusable input has a `validation` block.
- [ ] Module `README.md` inputs/outputs tables match the code.
- [ ] At least `examples/basic` exists and is covered by a contract run.
- [ ] Tests cover the defaults, the toggles, and the validations.
- [ ] `make manifest` has been run and `registry.json` is committed.
- [ ] Catalog entries in `README.md` and `docs/module-catalog.md` are current.
- [ ] Commit messages follow Conventional Commits, with breaking changes flagged.
- [ ] No real account ids, ARNs, bucket names, or credentials anywhere in the diff.

Releases are cut from `main` by automation — see [RELEASING.md](./RELEASING.md).
Questions and proposals are best raised as a Discussion in the repository or as a
comment on the pull request.
