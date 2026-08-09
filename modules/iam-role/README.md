# iam-role

A reusable IAM role module. The trust policy is assembled from whichever
principal types you supply — AWS service principals, IAM role/account ARNs, or
federated OIDC providers — and permissions are attached via managed and/or
inline policies. A permissions boundary can cap the role's effective access.

## Security posture

- **Least privilege by construction** — no permissions are granted unless you attach a policy.
- **Trust is explicit** — the module refuses to create a role with no trust source.
- **Confused-deputy protection** — cross-account trust supports `ExternalId` and MFA conditions.
- **Bounded blast radius** — an optional permissions boundary limits what the role can ever do, even with broad inline policies.

## Usage

### Service role (ECS task)

```hcl
module "task_role" {
  source = "github.com/<your-github-org>/terraform-module-registry//modules/iam-role?ref=v1.0.0"

  role_name                  = "example-app-task"
  trusted_service_principals = ["ecs-tasks.amazonaws.com"]
  managed_policy_arns        = ["arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"]

  tags = {
    Environment = "prod"
    Owner       = "platform"
  }
}
```

### Cross-account role with a boundary

```hcl
module "deployer" {
  source = "github.com/<your-github-org>/terraform-module-registry//modules/iam-role?ref=v1.0.0"

  role_name                = "example-deployer"
  trusted_account_ids      = ["123456789012"]
  require_mfa              = true
  external_id              = "example-external-id"
  permissions_boundary_arn = "arn:aws:iam::123456789012:policy/example-boundary"

  inline_policies = {
    deploy = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "arn:aws:s3:::example-artifacts/*"
      }]
    })
  }
}
```

### OIDC (GitHub Actions)

```hcl
module "ci_role" {
  source = "github.com/<your-github-org>/terraform-module-registry//modules/iam-role?ref=v1.0.0"

  role_name = "example-ci"

  oidc_providers = [{
    provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    audience_key = "token.actions.githubusercontent.com:aud"
    audiences    = ["sts.amazonaws.com"]
    subject_key  = "token.actions.githubusercontent.com:sub"
    subjects     = ["repo:<your-github-org>/example-repo:ref:refs/heads/main"]
  }]
}
```

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `role_name` | `string` | — | Name of the IAM role. |
| `path` | `string` | `/` | IAM path for the role. |
| `description` | `string` | managed note | Role description. |
| `trusted_service_principals` | `list(string)` | `[]` | AWS service principals that may assume the role. |
| `trusted_role_arns` | `list(string)` | `[]` | Role/user ARNs that may assume the role. |
| `trusted_account_ids` | `list(string)` | `[]` | Account IDs whose principals may assume the role. |
| `oidc_providers` | `list(object)` | `[]` | Federated OIDC trust entries. |
| `require_mfa` | `bool` | `false` | Require MFA for AWS-principal trust. |
| `external_id` | `string` | `null` | ExternalId condition for cross-account trust. |
| `max_session_duration` | `number` | `3600` | Max session duration (3600–43200s). |
| `managed_policy_arns` | `list(string)` | `[]` | Managed policies to attach. |
| `inline_policies` | `map(string)` | `{}` | Inline policy name → JSON document. |
| `permissions_boundary_arn` | `string` | `null` | Permissions boundary policy ARN. |
| `force_detach_policies` | `bool` | `true` | Force-detach policies on destroy. |
| `tags` | `map(string)` | `{}` | Tags applied to the role. |

## Outputs

| Name | Description |
|------|-------------|
| `role_name` | Role name. |
| `role_arn` | Role ARN. |
| `role_id` | Stable unique ID. |
| `assume_role_policy_json` | Rendered trust policy. |
| `attached_managed_policy_arns` | Attached managed policy ARNs. |
| `inline_policy_names` | Inline policy names created. |

## Examples

- [`examples/basic`](./examples/basic) — service role for ECS tasks.
- [`examples/complete`](./examples/complete) — cross-account role with MFA, ExternalId, boundary, and inline policy.
