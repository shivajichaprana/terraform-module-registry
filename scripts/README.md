# scripts

Maintenance tooling for the module registry.

## `generate_manifest.py`

Generates `registry.json`, the machine-readable index of published modules, from the
module sources. It discovers every module under `modules/`, parses each one for its
provider requirements, minimum Terraform version, inputs (and which are required),
outputs, and examples, and computes a content hash over the module's root `*.tf`
files. Curated fields — a module's `summary` and lifecycle `status` — are preserved
from the existing manifest, so regenerating is idempotent against a maintained file.

The tool uses only the Python standard library (Python 3.9+).

```bash
# Print the manifest to stdout
python3 scripts/generate_manifest.py

# Write it to registry.json
python3 scripts/generate_manifest.py --write

# Fail (exit 1) if registry.json is out of date — used in CI
python3 scripts/generate_manifest.py --check

# Stamp a release version while regenerating (used by release automation)
python3 scripts/generate_manifest.py --write --set-version 1.2.0
```
