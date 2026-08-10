# Native unit tests for the iam-role module.
#
# Runs plan against a mocked AWS provider and asserts on plan-known values:
# role configuration arguments, policy attachment/inline counts, and outputs
# derived from inputs. The rendered trust policy JSON is provider-computed and
# therefore not asserted; instead the trust-source precondition is exercised
# directly. Negative runs prove the input validations reject bad configuration.

mock_provider "aws" {}

variables {
  role_name = "app-task-role"
}

# --- Service-principal role, secure defaults --------------------------------

run "service_role_defaults" {
  command = plan

  module {
    source = "../modules/iam-role"
  }

  variables {
    role_name                  = "app-task-role"
    trusted_service_principals = ["ecs-tasks.amazonaws.com"]
  }

  assert {
    condition     = aws_iam_role.this.name == "app-task-role"
    error_message = "Role name should match the input."
  }

  assert {
    condition     = aws_iam_role.this.path == "/"
    error_message = "Path should default to /."
  }

  assert {
    condition     = aws_iam_role.this.max_session_duration == 3600
    error_message = "Max session duration should default to 3600 seconds."
  }

  assert {
    condition     = aws_iam_role.this.force_detach_policies == true
    error_message = "force_detach_policies should default to true."
  }

  assert {
    condition     = aws_iam_role.this.permissions_boundary == null
    error_message = "No permissions boundary should be set by default."
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.managed) == 0
    error_message = "No managed policies should be attached by default."
  }

  assert {
    condition     = length(aws_iam_role_policy.inline) == 0
    error_message = "No inline policies should exist by default."
  }

  assert {
    condition     = length(output.inline_policy_names) == 0
    error_message = "inline_policy_names output should be empty by default."
  }

  assert {
    condition     = output.role_name == "app-task-role"
    error_message = "role_name output should surface the role name."
  }
}

# --- Managed + inline policies ---------------------------------------------

run "managed_and_inline_policies" {
  command = plan

  module {
    source = "../modules/iam-role"
  }

  variables {
    role_name                  = "app-task-role"
    trusted_service_principals = ["ecs-tasks.amazonaws.com"]
    managed_policy_arns = [
      "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess",
      "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
    ]
    inline_policies = {
      "s3-object-read" = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"s3:GetObject\"],\"Resource\":\"*\"}]}"
    }
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.managed) == 2
    error_message = "Two managed policies should be attached."
  }

  assert {
    condition     = length(aws_iam_role_policy.inline) == 1
    error_message = "One inline policy should be created."
  }

  assert {
    condition     = length(output.attached_managed_policy_arns) == 2
    error_message = "attached_managed_policy_arns output should list both ARNs."
  }

  assert {
    condition     = contains(output.inline_policy_names, "s3-object-read")
    error_message = "inline_policy_names output should include the inline policy name."
  }
}

# --- Cross-account trust with boundary and longer session ------------------

run "cross_account_with_boundary" {
  command = plan

  module {
    source = "../modules/iam-role"
  }

  variables {
    role_name                = "cross-account-deployer"
    path                     = "/service-roles/"
    trusted_account_ids      = ["123456789012"]
    require_mfa              = true
    external_id              = "shared-secret-handshake"
    permissions_boundary_arn = "arn:aws:iam::123456789012:policy/boundary"
    max_session_duration     = 7200
  }

  assert {
    condition     = aws_iam_role.this.max_session_duration == 7200
    error_message = "Max session duration should honor the input."
  }

  assert {
    condition     = aws_iam_role.this.path == "/service-roles/"
    error_message = "Path should honor the input."
  }

  assert {
    condition     = aws_iam_role.this.permissions_boundary == "arn:aws:iam::123456789012:policy/boundary"
    error_message = "Permissions boundary should be attached to the role."
  }
}

# --- OIDC-only trust satisfies the precondition ----------------------------

run "oidc_federation_only" {
  command = plan

  module {
    source = "../modules/iam-role"
  }

  variables {
    role_name = "github-oidc-deployer"
    oidc_providers = [
      {
        provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
        audience_key = "token.actions.githubusercontent.com:aud"
        audiences    = ["sts.amazonaws.com"]
        subject_key  = "token.actions.githubusercontent.com:sub"
        subjects     = ["repo:<your-github-org>/<your-repo>:ref:refs/heads/main"]
      }
    ]
  }

  assert {
    condition     = aws_iam_role.this.name == "github-oidc-deployer"
    error_message = "An OIDC-only trust configuration should plan cleanly and create the role."
  }
}

# --- Input validation and precondition (negative) --------------------------

run "reject_invalid_role_name" {
  command = plan

  module {
    source = "../modules/iam-role"
  }

  variables {
    role_name                  = "bad name!"
    trusted_service_principals = ["ecs-tasks.amazonaws.com"]
  }

  expect_failures = [var.role_name]
}

run "reject_invalid_path" {
  command = plan

  module {
    source = "../modules/iam-role"
  }

  variables {
    role_name                  = "app-task-role"
    path                       = "no-slashes"
    trusted_service_principals = ["ecs-tasks.amazonaws.com"]
  }

  expect_failures = [var.path]
}

run "reject_non_arn_trusted_role" {
  command = plan

  module {
    source = "../modules/iam-role"
  }

  variables {
    role_name         = "app-task-role"
    trusted_role_arns = ["not-an-arn"]
  }

  expect_failures = [var.trusted_role_arns]
}

run "reject_bad_account_id" {
  command = plan

  module {
    source = "../modules/iam-role"
  }

  variables {
    role_name           = "app-task-role"
    trusted_account_ids = ["123"]
  }

  expect_failures = [var.trusted_account_ids]
}

run "reject_session_too_long" {
  command = plan

  module {
    source = "../modules/iam-role"
  }

  variables {
    role_name                  = "app-task-role"
    trusted_service_principals = ["ecs-tasks.amazonaws.com"]
    max_session_duration       = 50000
  }

  expect_failures = [var.max_session_duration]
}

run "reject_invalid_inline_json" {
  command = plan

  module {
    source = "../modules/iam-role"
  }

  variables {
    role_name                  = "app-task-role"
    trusted_service_principals = ["ecs-tasks.amazonaws.com"]
    inline_policies = {
      "broken" = "{ this is not json"
    }
  }

  expect_failures = [var.inline_policies]
}

run "reject_no_trust_source" {
  command = plan

  module {
    source = "../modules/iam-role"
  }

  variables {
    role_name = "orphan-role"
  }

  expect_failures = [aws_iam_role.this]
}
