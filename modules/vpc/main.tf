# Opinionated VPC with public/private subnets across multiple availability
# zones, optional NAT gateway(s) for private egress, and encrypted VPC Flow
# Logs. Subnets are driven by per-AZ CIDR lists so the topology stays explicit.

locals {
  # Pair each subnet CIDR with its availability zone, keyed for for_each so
  # adding or removing a zone does not force-replace unrelated subnets.
  public_subnets = {
    for idx, cidr in var.public_subnet_cidrs :
    var.availability_zones[idx] => {
      cidr = cidr
      az   = var.availability_zones[idx]
    }
  }

  private_subnets = {
    for idx, cidr in var.private_subnet_cidrs :
    var.availability_zones[idx] => {
      cidr = cidr
      az   = var.availability_zones[idx]
    }
  }

  has_public_subnets  = length(var.public_subnet_cidrs) > 0
  has_private_subnets = length(var.private_subnet_cidrs) > 0

  # NAT gateways only make sense with both a public subnet to host them and a
  # private subnet needing egress.
  create_nat = var.enable_nat_gateway && local.has_public_subnets && local.has_private_subnets

  # One NAT per AZ, or a single shared NAT keyed to the first public AZ.
  nat_azs = local.create_nat ? (
    var.single_nat_gateway ? [var.availability_zones[0]] : keys(local.public_subnets)
  ) : []

  nat_gateways = { for az in local.nat_azs : az => az }

  # Private route tables: one per AZ (each pointing at its zonal NAT) when NAT
  # is per-AZ, otherwise a single shared table.
  private_route_table_keys = local.has_private_subnets ? (
    (local.create_nat && !var.single_nat_gateway) ? keys(local.private_subnets) : ["shared"]
  ) : []
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = var.enable_dns_support
  enable_dns_hostnames = var.enable_dns_hostnames

  tags = merge(var.tags, { Name = var.name })

  # Reject a subnet layout that references zones the module was not given.
  lifecycle {
    precondition {
      condition     = length(var.public_subnet_cidrs) <= length(var.availability_zones)
      error_message = "public_subnet_cidrs must not have more entries than availability_zones."
    }
    precondition {
      condition     = length(var.private_subnet_cidrs) <= length(var.availability_zones)
      error_message = "private_subnet_cidrs must not have more entries than availability_zones."
    }
  }
}

resource "aws_internet_gateway" "this" {
  count = local.has_public_subnets ? 1 : 0

  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-igw" })
}

resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = var.map_public_ip_on_launch

  tags = merge(var.tags, {
    Name = "${var.name}-public-${each.value.az}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  tags = merge(var.tags, {
    Name = "${var.name}-private-${each.value.az}"
    Tier = "private"
  })
}

# --- NAT gateways -----------------------------------------------------------

resource "aws_eip" "nat" {
  for_each = local.nat_gateways

  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.name}-nat-${each.key}" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  for_each = local.nat_gateways

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id
  tags          = merge(var.tags, { Name = "${var.name}-nat-${each.key}" })

  depends_on = [aws_internet_gateway.this]
}

# --- Public routing ---------------------------------------------------------

resource "aws_route_table" "public" {
  count = local.has_public_subnets ? 1 : 0

  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-public" })
}

resource "aws_route" "public_internet" {
  count = local.has_public_subnets ? 1 : 0

  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id
}

resource "aws_route_table_association" "public" {
  for_each = local.public_subnets

  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public[0].id
}

# --- Private routing --------------------------------------------------------

resource "aws_route_table" "private" {
  for_each = toset(local.private_route_table_keys)

  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-private-${each.key}" })
}

resource "aws_route" "private_nat" {
  # Only emit a default route when NAT exists. The route table key maps to a
  # zonal NAT when per-AZ, or to the single shared NAT otherwise.
  for_each = local.create_nat ? toset(local.private_route_table_keys) : toset([])

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id = var.single_nat_gateway ? (
    aws_nat_gateway.this[local.nat_azs[0]].id
  ) : aws_nat_gateway.this[each.key].id
}

resource "aws_route_table_association" "private" {
  for_each = local.private_subnets

  subnet_id = aws_subnet.private[each.key].id
  route_table_id = (local.create_nat && !var.single_nat_gateway) ? (
    aws_route_table.private[each.key].id
  ) : aws_route_table.private["shared"].id
}

# --- VPC Flow Logs ----------------------------------------------------------

data "aws_iam_policy_document" "flow_log_assume" {
  count = var.enable_flow_logs ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "flow_log_permissions" {
  count = var.enable_flow_logs ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.flow_log[0].arn}:*"]
  }
}

resource "aws_cloudwatch_log_group" "flow_log" {
  count = var.enable_flow_logs ? 1 : 0

  name              = "/vpc/flow-logs/${var.name}"
  retention_in_days = var.flow_log_retention_days
  kms_key_id        = var.flow_log_kms_key_arn
  tags              = var.tags
}

resource "aws_iam_role" "flow_log" {
  count = var.enable_flow_logs ? 1 : 0

  name               = "${var.name}-flow-log"
  assume_role_policy = data.aws_iam_policy_document.flow_log_assume[0].json
  tags               = var.tags
}

resource "aws_iam_role_policy" "flow_log" {
  count = var.enable_flow_logs ? 1 : 0

  name   = "flow-log-delivery"
  role   = aws_iam_role.flow_log[0].id
  policy = data.aws_iam_policy_document.flow_log_permissions[0].json
}

resource "aws_flow_log" "this" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id                   = aws_vpc.this.id
  traffic_type             = "ALL"
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.flow_log[0].arn
  iam_role_arn             = aws_iam_role.flow_log[0].arn
  max_aggregation_interval = 600

  tags = merge(var.tags, { Name = "${var.name}-flow-log" })
}
