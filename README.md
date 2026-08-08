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
| `LICENSE` | MIT license. |

## Modules

| Module | Summary | Status |
|--------|---------|--------|
| [`s3-bucket`](./modules/s3-bucket) | Hardened S3 bucket with encryption, public-access blocking, and TLS enforcement. | stable |

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

## Contributing a module

1. Create `modules/<name>/` with `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, and a `README.md`.
2. Add secure defaults and `validation` blocks to every input that can be misused.
3. Provide at least a `basic` example under `examples/`.
4. Register the module in `registry.json`.
5. Run `terraform fmt` and `terraform validate` before opening a pull request.

## License

MIT — see [LICENSE](./LICENSE).
