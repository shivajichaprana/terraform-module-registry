# Releasing

Releases are automated from [Conventional Commit](https://www.conventionalcommits.org/)
messages. You do not pick version numbers by hand — the commit history determines
the next [Semantic Version](https://semver.org/), the changelog is regenerated, the
module manifest is stamped and refreshed, and a tag plus release are published.

## Versioning policy

The registry is versioned as a whole. Consumers pin an immutable tag, never `main`:

```hcl
source = "github.com/<your-github-org>/terraform-module-registry//modules/s3-bucket?ref=v1.0.0"
```

The next version is derived from the commit types since the last release:

| Commit type | Example | Version bump |
|-------------|---------|--------------|
| `fix:`, `perf:`, `refactor:`, `revert:` | `fix(vpc): correct NAT route association` | patch (`x.y.Z`) |
| `feat:` | `feat(modules): add cloudfront module` | minor (`x.Y.0`) |
| any type with `!` or a `BREAKING CHANGE:` footer | `feat(iam-role)!: drop deprecated input` | major (`X.0.0`) |
| `build:`, `ci:`, `test:`, `chore:` | `chore(deps): bump provider constraint` | no release |

A breaking change to a module's input or output contract **must** be flagged with
`!` or a `BREAKING CHANGE:` footer so consumers are not surprised by a minor bump.

## Commit message enforcement

`commitlint` (configured in `.commitlintrc.json`) validates commit messages against
the Conventional Commits specification. Run it locally over your latest commit:

```bash
npm install
npm run commitlint
```

## The module manifest

`registry.json` is the machine-readable index of published modules. It is generated
from the module sources — never edited by hand — by `scripts/generate_manifest.py`,
which parses each module's provider requirements, minimum Terraform version, inputs
(and which are required), outputs, examples, and a content hash.

```bash
# Regenerate the manifest after changing a module
npm run manifest          # python3 scripts/generate_manifest.py --write

# Verify the committed manifest matches the sources (used in CI)
npm run manifest:check    # python3 scripts/generate_manifest.py --check
```

During a release the manifest's `version` field is stamped to the release version
automatically (see the `@semantic-release/exec` step in `.releaserc.json`).

## Cutting a release

Releases run from an automation context with a token that may push tags and create
releases. To preview what the next release would be without publishing anything:

```bash
npm install
npm run release:dry
```

The real release (`npm run release`) then, in order:

1. analyzes the commits and computes the next version;
2. regenerates and version-stamps `registry.json`;
3. updates `CHANGELOG.md`;
4. commits the changelog, manifest, and `package.json`;
5. creates the `vX.Y.Z` tag and a GitHub release with generated notes.
