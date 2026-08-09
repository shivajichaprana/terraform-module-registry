# Reusable IAM role. The trust policy is assembled from whichever principal
# types the caller supplies (AWS services, role/account ARNs, or OIDC
# federation); permissions come from managed and inline policies, and an
# optional permissions boundary caps the role's effective access.

locals {
  has_service_trust = length(var.trusted_service_principals) > 0
  has_aws_trust     = length(var.trusted_role_arns) > 0 || length(var.trusted_account_ids) > 0
  has_oidc_trust    = length(var.oidc_providers) > 0

  # Root-account principals for account-wide trust.
  account_principal_arns = [for id in var.trusted_account_ids : "arn:aws:iam::${id}:root"]
  aws_principal_arns     = concat(var.trusted_role_arns, local.account_principal_arns)
}

data "aws_iam_policy_document" "assume_role" {
  # Trust for AWS service principals (for example ecs-tasks, lambda).
  dynamic "statement" {
    for_each = local.has_service_trust ? [1] : []

    content {
      sid     = "ServiceTrust"
      effect  = "Allow"
      actions = ["sts:AssumeRole"]

      principals {
        type        = "Service"
        identifiers = var.trusted_service_principals
      }
    }
  }

  # Trust for IAM role/user ARNs and whole accounts.
  dynamic "statement" {
    for_each = local.has_aws_trust ? [1] : []

    content {
      sid     = "AwsPrincipalTrust"
      effect  = "Allow"
      actions = ["sts:AssumeRole"]

      principals {
        type        = "AWS"
        identifiers = local.aws_principal_arns
      }

      dynamic "condition" {
        for_each = var.require_mfa ? [1] : []
        content {
          test     = "Bool"
          variable = "aws:MultiFactorAuthPresent"
          values   = ["true"]
        }
      }

      dynamic "condition" {
        for_each = var.external_id != null ? [1] : []
        content {
          test     = "StringEquals"
          variable = "sts:ExternalId"
          values   = [var.external_id]
        }
      }
    }
  }

  # Federated OIDC trust (for example GitHub Actions, EKS IRSA).
  dynamic "statement" {
    for_each = { for idx, p in var.oidc_providers : idx => p }

    content {
      sid     = "OidcTrust${statement.key}"
      effect  = "Allow"
      actions = ["sts:AssumeRoleWithWebIdentity"]

      principals {
        type        = "Federated"
        identifiers = [statement.value.provider_arn]
      }

      condition {
        test     = "StringEquals"
        variable = statement.value.audience_key
        values   = statement.value.audiences
      }

      dynamic "condition" {
        for_each = statement.value.subject_key != null ? [1] : []
        content {
          test     = "StringLike"
          variable = statement.value.subject_key
          values   = statement.value.subjects
        }
      }
    }
  }
}

resource "aws_iam_role" "this" {
  name                  = var.role_name
  path                  = var.path
  description           = var.description
  assume_role_policy    = data.aws_iam_policy_document.assume_role.json
  max_session_duration  = var.max_session_duration
  permissions_boundary  = var.permissions_boundary_arn
  force_detach_policies = var.force_detach_policies
  tags                  = var.tags

  # A role with no trust relationship is unusable; fail at plan time.
  lifecycle {
    precondition {
      condition     = local.has_service_trust || local.has_aws_trust || local.has_oidc_trust
      error_message = "at least one trust source is required: trusted_service_principals, trusted_role_arns, trusted_account_ids, or oidc_providers."
    }
  }
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each = toset(var.managed_policy_arns)

  role       = aws_iam_role.this.name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "inline" {
  for_each = var.inline_policies

  name   = each.key
  role   = aws_iam_role.this.id
  policy = each.value
}
