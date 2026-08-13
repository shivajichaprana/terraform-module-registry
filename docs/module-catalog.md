# Module catalog

Every published module, what it is for, and the contract it exposes. The
machine-readable version of this catalog is [`registry.json`](../registry.json),
which is generated from the module sources.

## Selection guide

| You need… | Use | Notes |
|-----------|-----|-------|
| Object storage for logs, artifacts, or data | [`s3-bucket`](#s3-bucket) | Private, encrypted, TLS-only out of the box. |
| A network to run workloads in | [`vpc`](#vpc) | Public/private subnets across the AZs you name, NAT egress, Flow Logs. |
| An identity for a workload, a pipeline, or another account | [`iam-role`](#iam-role) | Trust is assembled from the principal types you supply. |
| Several of the above wired together | compose them | Pass outputs between calls; see [Composition patterns](#composition-patterns). |

## Common contract

All modules follow the same conventions, so switching between them holds no surprises.

| Aspect | Convention |
|--------|-----------|
| Terraform version | `>= 1.6.0` |
| Providers | `aws` (`>= 5.0, < 6.0`) |
| Tagging | Every module takes a `tags` map applied to the resources it creates. |
| Validation | Inputs that can be misused carry `validation` blocks; cross-input rules use `lifecycle.precondition`. |
| Failure timing | Misconfiguration fails at plan time, never at apply time. |
| Examples | At least `examples/basic`; most also ship `examples/complete`. |
| Source pinning | `github.com/<your-github-org>/terraform-module-registry//modules/<name>?ref=vX.Y.Z` |

---

## s3-bucket

**Hardened S3 bucket.** A bare call produces a private, encrypted, versioned,
TLS-only bucket — nothing extra to remember.

| | |
|---|---|
| Path | [`modules/s3-bucket`](../modules/s3-bucket) |
| Required inputs | `bucket_name` |
| Inputs / outputs | 13 / 6 |
| Examples | `basic`, `complete` |
| Status | stable |

**Security posture**

- All four public-access-block settings default to `true`.
- Object ownership is `BucketOwnerEnforced`, so ACLs are disabled.
- Encryption is always on: SSE-S3 (`AES256`) by default, or SSE-KMS with a Bucket Key when `kms_key_arn` is set.
- A bucket policy denies any request where `aws:SecureTransport` is `false` (on by default, `enforce_tls`).
- Versioning is enabled, and incomplete multipart uploads are aborted after a configurable number of days.

**Key inputs**

| Input | Default | Why you would change it |
|-------|---------|-------------------------|
| `kms_key_arn` | `null` | Switch from SSE-S3 to a customer-managed key. |
| `lifecycle_rules` | `[]` | Tier objects to IA/Glacier or expire them on a schedule. |
| `logging` | `null` | Send server access logs to a central log bucket. |
| `enforce_tls` | `true` | Only lower when a legacy client genuinely cannot use TLS. |
| `additional_policy_statements` | `[]` | Grant cross-account reads or add explicit denies. |

**Key outputs** — `bucket_id`, `bucket_arn`, `bucket_regional_domain_name`,
`sse_algorithm`, `bucket_policy_attached`.

```hcl
module "artifacts" {
  source = "github.com/<your-github-org>/terraform-module-registry//modules/s3-bucket?ref=v1.0.0"

  bucket_name = "example-app-artifacts"
  kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/<key-id>"

  lifecycle_rules = [{
    id = "archive-old-objects"
    transitions = [
      { days = 30, storage_class = "STANDARD_IA" },
      { days = 90, storage_class = "GLACIER" },
    ]
    noncurrent_version_expiration = 365
  }]
}
```

Full reference: [`modules/s3-bucket/README.md`](../modules/s3-bucket/README.md).

---

## vpc

**Multi-AZ VPC.** Public and private subnets spread across the availability zones
you name, private egress through NAT, and encrypted Flow Logs.

| | |
|---|---|
| Path | [`modules/vpc`](../modules/vpc) |
| Required inputs | `name`, `cidr_block`, `availability_zones` |
| Inputs / outputs | 14 / 13 |
| Examples | `basic`, `complete` |
| Status | stable |

**Security posture**

- Flow Logs are on by default, delivered to a CloudWatch Logs group with configurable retention and optional KMS encryption.
- Private subnets do not auto-assign public IPs; their only egress path is NAT.
- The address plan is explicit — subnets come from per-AZ CIDR lists rather than being computed implicitly.
- NAT is fault-tolerant by default (one gateway per AZ); `single_nat_gateway` trades resilience for cost.

**Key inputs**

| Input | Default | Why you would change it |
|-------|---------|-------------------------|
| `public_subnet_cidrs` / `private_subnet_cidrs` | `[]` | Choose the tiers you need; omit one to build a private-only or public-only network. |
| `enable_nat_gateway` | `true` | Disable for a network with no private egress requirement. |
| `single_nat_gateway` | `false` | Share one NAT in non-production to cut cost. |
| `flow_log_retention_days` | `90` | Match your log-retention policy. |
| `flow_log_kms_key_arn` | `null` | Encrypt the Flow Logs group with a customer-managed key. |

**Key outputs** — `vpc_id`, `public_subnet_ids` / `private_subnet_ids` (maps keyed
by AZ), the matching `*_id_list` forms for ordered consumption,
`nat_gateway_ids`, `flow_log_group_name`.

Subnet IDs are exposed both as AZ-keyed maps and as lists: use the map when a
consumer needs zone awareness, the list when it just needs a set of subnets.

```hcl
module "network" {
  source = "github.com/<your-github-org>/terraform-module-registry//modules/vpc?ref=v1.0.0"

  name                 = "platform"
  cidr_block           = "10.0.0.0/16"
  availability_zones   = ["us-east-1a", "us-east-1b"]
  public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
}
```

Full reference: [`modules/vpc/README.md`](../modules/vpc/README.md).

---

## iam-role

**Reusable IAM role.** The trust policy is assembled from whichever principal
types you supply — AWS service principals, role/account ARNs, or federated OIDC
providers — and permissions come from managed and/or inline policies.

| | |
|---|---|
| Path | [`modules/iam-role`](../modules/iam-role) |
| Required inputs | `role_name` |
| Inputs / outputs | 15 / 6 |
| Examples | `basic`, `complete` |
| Status | stable |

**Security posture**

- No permissions are granted unless you attach a policy — least privilege by construction.
- The module refuses to create a role with no trust source at all.
- Cross-account trust supports `ExternalId` and MFA conditions to defeat the confused-deputy problem.
- An optional permissions boundary caps the role's effective access no matter how broad its policies are.

**Trust shapes**

| Input | Produces |
|-------|----------|
| `trusted_service_principals` | A `Service` principal statement — workload roles (ECS tasks, Lambda, EC2). |
| `trusted_role_arns` / `trusted_account_ids` | An `AWS` principal statement, optionally conditioned on `ExternalId` and MFA. |
| `oidc_providers` | A `Federated` statement per provider with an audience match and optional subject match — keyless CI. |

**Key outputs** — `role_arn`, `role_name`, `assume_role_policy_json`,
`attached_managed_policy_arns`, `inline_policy_names`.

```hcl
module "ci_role" {
  source = "github.com/<your-github-org>/terraform-module-registry//modules/iam-role?ref=v1.0.0"

  role_name                = "example-ci"
  permissions_boundary_arn = "arn:aws:iam::123456789012:policy/example-boundary"

  oidc_providers = [{
    provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    audience_key = "token.actions.githubusercontent.com:aud"
    audiences    = ["sts.amazonaws.com"]
    subject_key  = "token.actions.githubusercontent.com:sub"
    subjects     = ["repo:<your-github-org>/example-repo:ref:refs/heads/main"]
  }]
}
```

Full reference: [`modules/iam-role/README.md`](../modules/iam-role/README.md).

---

## Composition patterns

Modules are composed by passing outputs between calls, never by nesting one
module's source inside another. That keeps each module independently testable and
independently versioned.

**Workload network + storage + identity**

```hcl
module "network" {
  source = "${local.registry}/vpc?ref=v1.0.0"
  # ...
}

module "artifacts" {
  source = "${local.registry}/s3-bucket?ref=v1.0.0"
  # ...
}

module "task_role" {
  source = "${local.registry}/iam-role?ref=v1.0.0"

  role_name                  = "example-platform-task"
  trusted_service_principals = ["ecs-tasks.amazonaws.com"]

  inline_policies = {
    artifacts-read = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${module.artifacts.bucket_arn}/*"
      }]
    })
  }
}

# Place a workload in the private subnets:
#   subnet_ids = module.network.private_subnet_id_list
```

**Encrypted bucket with a dedicated key** — create the KMS key in your own
configuration and pass its ARN as `kms_key_arn`; the module does not manage key
lifecycle, so key rotation and policy stay under the caller's control.

**Keyless pipeline identity** — combine `iam-role`'s `oidc_providers` trust with a
`permissions_boundary_arn` so an automation role can never exceed its ceiling
even if its inline policy is later widened.

## Versioning and compatibility

The registry is versioned as a whole: a tag such as `v1.0.0` pins every module at
once. Because a module's inputs and outputs are its public contract, a breaking
change to either is released as a major version and flagged with `!` or a
`BREAKING CHANGE:` footer in the commit — see [RELEASING.md](../RELEASING.md).

| Change | Version bump |
|--------|--------------|
| New module, or a new optional input with a safe default | minor |
| Bug fix that preserves the contract | patch |
| Removing or renaming an input or output, or changing a default in a way that alters existing infrastructure | major |

Pin `?ref=vX.Y.Z` in consuming configurations and upgrade deliberately by
bumping the ref and reviewing the plan.

## Manifest fields

`registry.json` carries a generated entry per module:

| Field | Meaning |
|-------|---------|
| `name`, `path` | Module identifier and location under `modules/`. |
| `summary`, `status` | Curated description and lifecycle stage (preserved across regeneration). |
| `providers`, `min_terraform_version` | Parsed from the module's `versions.tf`. |
| `inputs.count`, `inputs.required` | Parsed from `variables.tf`; an input is required when it has no default. |
| `outputs.count` | Parsed from `outputs.tf`. |
| `examples` | Example directories discovered under the module. |
| `content_hash` | SHA-256 over the module's root `*.tf` files, so a source change is visible in the index. |

Regenerate with `make manifest`; `make manifest-check` fails if the committed
manifest has drifted from the sources.
