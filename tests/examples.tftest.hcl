# Example-based contract tests.
#
# Every published module ships `examples/basic` and `examples/complete`
# directories that document how a consumer is expected to call it. These runs
# reproduce each example's inputs against the module and assert that the output
# contract those examples advertise still holds — so a change that silently
# alters a documented output, encryption mode, or topology fails here.
#
# Like the unit suites, runs execute `command = plan` against a mocked AWS
# provider (offline, nothing created) and assert only on plan-known values:
# module outputs derived from locals, configuration arguments set from inputs,
# and resource counts driven by inputs. The example directories themselves are
# additionally `terraform validate`d in CI, which exercises their provider and
# variable wiring.

mock_provider "aws" {
  # aws_iam_role and aws_iam_policy both validate that the policy they are given
  # is a JSON object, so the mocked document has to return real JSON rather than
  # the placeholder string the provider mock would otherwise invent.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

# --- s3-bucket: basic example ----------------------------------------------
# Minimal private, encrypted, TLS-only bucket using module defaults.

run "s3_bucket_basic_example" {
  command = plan

  module {
    source = "../modules/s3-bucket"
  }

  variables {
    bucket_name = "example-basic-bucket-123456789012"
    tags = {
      Environment = "dev"
      Owner       = "platform"
    }
  }

  assert {
    condition     = aws_s3_bucket.this.bucket == "example-basic-bucket-123456789012"
    error_message = "Bucket name should match the example input."
  }

  assert {
    condition     = output.sse_algorithm == "AES256"
    error_message = "Without a KMS key the basic example must fall back to SSE-S3 (AES256)."
  }

  assert {
    condition     = output.bucket_policy_attached == true
    error_message = "TLS enforcement is on by default, so a bucket policy must be attached."
  }
}

# --- s3-bucket: complete example -------------------------------------------
# SSE-KMS with a Bucket Key, lifecycle transitions, and access logging.

run "s3_bucket_complete_example" {
  command = plan

  module {
    source = "../modules/s3-bucket"
  }

  variables {
    bucket_name        = "example-complete-bucket-123456789012"
    kms_key_arn        = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
    bucket_key_enabled = true
    versioning_enabled = true

    lifecycle_rules = [
      {
        id     = "archive-and-expire"
        prefix = "archive/"
        transitions = [
          { days = 30, storage_class = "STANDARD_IA" },
          { days = 90, storage_class = "GLACIER" },
        ]
        expiration_days               = 3650
        noncurrent_version_expiration = 365
      },
    ]

    logging = {
      target_bucket = "example-central-access-logs"
      target_prefix = "complete-bucket/"
    }

    tags = {
      Environment = "prod"
      Owner       = "platform"
      CostCenter  = "cc-1001"
    }
  }

  assert {
    condition     = aws_s3_bucket.this.bucket == "example-complete-bucket-123456789012"
    error_message = "Bucket name should match the example input."
  }

  assert {
    condition     = output.sse_algorithm == "aws:kms"
    error_message = "Supplying a KMS key must select SSE-KMS encryption."
  }

  assert {
    condition     = output.bucket_policy_attached == true
    error_message = "The complete example enforces TLS, so a bucket policy must be attached."
  }
}

# --- vpc: basic example -----------------------------------------------------
# Two-AZ VPC with public/private subnets and fault-tolerant per-AZ NAT.

run "vpc_basic_example" {
  command = plan

  module {
    source = "../modules/vpc"
  }

  variables {
    name               = "example-basic"
    cidr_block         = "10.0.0.0/16"
    availability_zones = ["us-east-1a", "us-east-1b"]

    public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]
    private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]

    tags = {
      Environment = "dev"
      Owner       = "platform"
    }
  }

  assert {
    condition     = aws_vpc.this.cidr_block == "10.0.0.0/16"
    error_message = "VPC CIDR should match the example input."
  }

  assert {
    condition     = length(aws_subnet.public) == 2 && length(aws_subnet.private) == 2
    error_message = "The basic example should create one public and one private subnet per AZ."
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 2
    error_message = "The basic example defaults to fault-tolerant per-AZ NAT gateways."
  }

  assert {
    condition     = length(output.private_subnet_ids) == 2
    error_message = "private_subnet_ids output should surface one entry per AZ."
  }

  assert {
    condition     = output.flow_log_group_name == "/vpc/flow-logs/example-basic"
    error_message = "Flow logs default on and the group name derives from the VPC name."
  }
}

# --- vpc: complete example --------------------------------------------------
# Cost-optimized VPC: single shared NAT and KMS-encrypted Flow Logs.

run "vpc_complete_example" {
  command = plan

  module {
    source = "../modules/vpc"
  }

  variables {
    name               = "example-complete"
    cidr_block         = "10.20.0.0/16"
    availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]

    public_subnet_cidrs  = ["10.20.0.0/24", "10.20.1.0/24", "10.20.2.0/24"]
    private_subnet_cidrs = ["10.20.10.0/24", "10.20.11.0/24", "10.20.12.0/24"]

    single_nat_gateway      = true
    flow_log_retention_days = 365
    flow_log_kms_key_arn    = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"

    tags = {
      Environment = "prod"
      Owner       = "platform"
      CostCenter  = "cc-1001"
    }
  }

  assert {
    condition     = aws_vpc.this.cidr_block == "10.20.0.0/16"
    error_message = "VPC CIDR should match the example input."
  }

  assert {
    condition     = length(aws_subnet.public) == 3 && length(aws_subnet.private) == 3
    error_message = "The complete example spans three AZs."
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 1
    error_message = "The complete example uses a single shared NAT gateway."
  }

  assert {
    condition     = aws_cloudwatch_log_group.flow_log[0].retention_in_days == 365
    error_message = "Flow log retention should honor the example input."
  }

  assert {
    condition     = output.flow_log_group_name == "/vpc/flow-logs/example-complete"
    error_message = "flow_log_group_name output should surface the derived group name."
  }
}

# --- iam-role: basic example ------------------------------------------------
# Service role assumable by ECS tasks with a read-only managed policy attached.

run "iam_role_basic_example" {
  command = plan

  module {
    source = "../modules/iam-role"
  }

  variables {
    role_name                  = "example-app-task"
    trusted_service_principals = ["ecs-tasks.amazonaws.com"]
    managed_policy_arns        = ["arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"]

    tags = {
      Environment = "dev"
      Owner       = "platform"
    }
  }

  assert {
    condition     = output.role_name == "example-app-task"
    error_message = "role_name output should match the example input."
  }

  assert {
    condition     = length(output.attached_managed_policy_arns) == 1
    error_message = "The basic example attaches exactly one managed policy."
  }

  assert {
    condition     = contains(output.attached_managed_policy_arns, "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess")
    error_message = "The attached managed policy should surface in the output."
  }

  assert {
    condition     = length(output.inline_policy_names) == 0
    error_message = "The basic example defines no inline policies."
  }
}

# --- iam-role: complete example ---------------------------------------------
# Cross-account role: MFA + ExternalId, permissions boundary, scoped inline.

run "iam_role_complete_example" {
  command = plan

  module {
    source = "../modules/iam-role"
  }

  variables {
    role_name            = "example-deployer"
    trusted_account_ids  = ["123456789012"]
    require_mfa          = true
    external_id          = "example-external-id"
    max_session_duration = 7200

    permissions_boundary_arn = "arn:aws:iam::123456789012:policy/example-boundary"

    inline_policies = {
      artifact-access = jsonencode({
        Version = "2012-10-17"
        Statement = [{
          Effect   = "Allow"
          Action   = ["s3:GetObject", "s3:PutObject"]
          Resource = "arn:aws:s3:::example-artifacts/*"
        }]
      })
    }

    tags = {
      Environment = "prod"
      Owner       = "platform"
      CostCenter  = "cc-1001"
    }
  }

  assert {
    condition     = output.role_name == "example-deployer"
    error_message = "role_name output should match the example input."
  }

  assert {
    condition     = aws_iam_role.this.max_session_duration == 7200
    error_message = "The complete example sets an extended session duration."
  }

  assert {
    condition     = aws_iam_role.this.permissions_boundary == "arn:aws:iam::123456789012:policy/example-boundary"
    error_message = "The permissions boundary should be applied from the example input."
  }

  assert {
    condition     = length(output.attached_managed_policy_arns) == 0
    error_message = "The complete example attaches no managed policies."
  }

  assert {
    condition     = length(output.inline_policy_names) == 1 && contains(output.inline_policy_names, "artifact-access")
    error_message = "The complete example defines a single scoped inline policy."
  }
}
