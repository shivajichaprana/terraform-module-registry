# Native unit tests for the vpc module.
#
# Runs plan against a mocked AWS provider and asserts on plan-known values:
# resource counts driven by inputs, and configuration arguments (CIDR,
# retention, traffic type, derived names). Negative runs prove the input
# validations reject bad topology.

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

variables {
  name               = "app-vpc"
  cidr_block         = "10.0.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b"]
}

# --- Per-AZ NAT topology (the fault-tolerant default) ----------------------

run "per_az_nat_topology" {
  command = plan

  module {
    source = "../modules/vpc"
  }

  variables {
    name                 = "app-vpc"
    cidr_block           = "10.0.0.0/16"
    availability_zones   = ["us-east-1a", "us-east-1b"]
    public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]
    private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
    enable_nat_gateway   = true
    single_nat_gateway   = false
    enable_flow_logs     = true
  }

  assert {
    condition     = aws_vpc.this.cidr_block == "10.0.0.0/16"
    error_message = "VPC CIDR should match the input."
  }

  assert {
    condition     = aws_vpc.this.enable_dns_support && aws_vpc.this.enable_dns_hostnames
    error_message = "DNS support and hostnames should default on."
  }

  assert {
    condition     = length(aws_subnet.public) == 2
    error_message = "Two public subnets expected, one per AZ."
  }

  assert {
    condition     = length(aws_subnet.private) == 2
    error_message = "Two private subnets expected, one per AZ."
  }

  assert {
    condition     = length(aws_internet_gateway.this) == 1
    error_message = "An internet gateway is required when public subnets exist."
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 2
    error_message = "Per-AZ NAT should create one NAT gateway per AZ."
  }

  assert {
    condition     = length(aws_eip.nat) == 2
    error_message = "Each NAT gateway needs its own Elastic IP."
  }

  assert {
    condition     = length(aws_route_table.private) == 2
    error_message = "Per-AZ NAT should create one private route table per AZ."
  }

  assert {
    condition     = length(aws_route_table.public) == 1
    error_message = "A single public route table is expected."
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.flow_log) == 1
    error_message = "Flow logs on by default should create one log group."
  }

  assert {
    condition     = aws_cloudwatch_log_group.flow_log[0].name == "/vpc/flow-logs/app-vpc"
    error_message = "Flow log group name should be derived from the VPC name."
  }

  assert {
    condition     = aws_cloudwatch_log_group.flow_log[0].retention_in_days == 90
    error_message = "Flow log retention should default to 90 days."
  }

  assert {
    condition     = aws_flow_log.this[0].traffic_type == "ALL"
    error_message = "Flow logs should capture ALL traffic."
  }

  assert {
    condition     = aws_flow_log.this[0].max_aggregation_interval == 600
    error_message = "Flow log aggregation interval should be 600 seconds."
  }

  assert {
    condition     = output.flow_log_group_name == "/vpc/flow-logs/app-vpc"
    error_message = "flow_log_group_name output should surface the log group name."
  }
}

# --- Single shared NAT ------------------------------------------------------

run "single_nat_shared_route_table" {
  command = plan

  module {
    source = "../modules/vpc"
  }

  variables {
    name                 = "app-vpc"
    cidr_block           = "10.0.0.0/16"
    availability_zones   = ["us-east-1a", "us-east-1b"]
    public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]
    private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
    enable_nat_gateway   = true
    single_nat_gateway   = true
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 1
    error_message = "A single shared NAT should create exactly one NAT gateway."
  }

  assert {
    condition     = length(aws_eip.nat) == 1
    error_message = "A single shared NAT needs exactly one Elastic IP."
  }

  assert {
    condition     = length(aws_route_table.private) == 1
    error_message = "A single shared NAT should use one shared private route table."
  }
}

# --- NAT disabled -----------------------------------------------------------

run "nat_disabled" {
  command = plan

  module {
    source = "../modules/vpc"
  }

  variables {
    name                 = "app-vpc"
    cidr_block           = "10.0.0.0/16"
    availability_zones   = ["us-east-1a", "us-east-1b"]
    public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]
    private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
    enable_nat_gateway   = false
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 0
    error_message = "No NAT gateways should be created when NAT is disabled."
  }

  assert {
    condition     = length(aws_route_table.private) == 1
    error_message = "Without NAT, private subnets share a single route table."
  }
}

# --- Private-only VPC (no public subnets, no IGW, no NAT) -------------------

run "private_only_no_igw" {
  command = plan

  module {
    source = "../modules/vpc"
  }

  variables {
    name                 = "app-vpc"
    cidr_block           = "10.0.0.0/16"
    availability_zones   = ["us-east-1a", "us-east-1b"]
    public_subnet_cidrs  = []
    private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
  }

  assert {
    condition     = length(aws_internet_gateway.this) == 0
    error_message = "No internet gateway should exist without public subnets."
  }

  assert {
    condition     = length(aws_subnet.public) == 0
    error_message = "No public subnets should exist."
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 0
    error_message = "NAT requires a public subnet to host it, so none should exist."
  }

  assert {
    condition     = length(aws_route_table.public) == 0
    error_message = "No public route table should exist without public subnets."
  }
}

# --- Flow logs toggles ------------------------------------------------------

run "flow_logs_disabled" {
  command = plan

  module {
    source = "../modules/vpc"
  }

  variables {
    name                 = "app-vpc"
    cidr_block           = "10.0.0.0/16"
    availability_zones   = ["us-east-1a", "us-east-1b"]
    private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
    enable_flow_logs     = false
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.flow_log) == 0
    error_message = "No flow log group should exist when flow logs are disabled."
  }

  assert {
    condition     = length(aws_flow_log.this) == 0
    error_message = "No flow log should exist when flow logs are disabled."
  }

  assert {
    condition     = output.flow_log_group_name == null
    error_message = "flow_log_group_name should be null when flow logs are disabled."
  }
}

run "flow_log_custom_retention_and_kms" {
  command = plan

  module {
    source = "../modules/vpc"
  }

  variables {
    name                    = "app-vpc"
    cidr_block              = "10.0.0.0/16"
    availability_zones      = ["us-east-1a", "us-east-1b"]
    private_subnet_cidrs    = ["10.0.10.0/24", "10.0.11.0/24"]
    enable_flow_logs        = true
    flow_log_retention_days = 365
    flow_log_kms_key_arn    = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = aws_cloudwatch_log_group.flow_log[0].retention_in_days == 365
    error_message = "Flow log retention should honor the input."
  }

  assert {
    condition     = aws_cloudwatch_log_group.flow_log[0].kms_key_id == "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
    error_message = "Flow log group should be encrypted with the supplied KMS key."
  }
}

# --- Input validation (negative) -------------------------------------------

run "reject_invalid_name" {
  command = plan

  module {
    source = "../modules/vpc"
  }

  variables {
    name               = "1-starts-with-digit"
    cidr_block         = "10.0.0.0/16"
    availability_zones = ["us-east-1a"]
  }

  expect_failures = [var.name]
}

run "reject_cidr_prefix_too_large" {
  command = plan

  module {
    source = "../modules/vpc"
  }

  variables {
    name               = "app-vpc"
    cidr_block         = "10.0.0.0/30"
    availability_zones = ["us-east-1a"]
  }

  expect_failures = [var.cidr_block]
}

run "reject_too_many_azs" {
  command = plan

  module {
    source = "../modules/vpc"
  }

  variables {
    name               = "app-vpc"
    cidr_block         = "10.0.0.0/16"
    availability_zones = ["a", "b", "c", "d", "e", "f", "g"]
  }

  expect_failures = [var.availability_zones]
}

run "reject_invalid_retention" {
  command = plan

  module {
    source = "../modules/vpc"
  }

  variables {
    name                    = "app-vpc"
    cidr_block              = "10.0.0.0/16"
    availability_zones      = ["us-east-1a"]
    flow_log_retention_days = 45
  }

  expect_failures = [var.flow_log_retention_days]
}

run "reject_invalid_public_subnet_cidr" {
  command = plan

  module {
    source = "../modules/vpc"
  }

  variables {
    name                = "app-vpc"
    cidr_block          = "10.0.0.0/16"
    availability_zones  = ["us-east-1a"]
    public_subnet_cidrs = ["not-a-cidr"]
  }

  expect_failures = [var.public_subnet_cidrs]
}
