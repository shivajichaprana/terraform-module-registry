# vpc

An opinionated multi-AZ VPC module. A minimal call yields a VPC with public and
private subnets spread across the requested availability zones, private egress
via NAT, and encrypted VPC Flow Logs — the safe baseline for most workloads.

## Security posture

- **Flow Logs on by default** — all traffic is captured to a CloudWatch Logs group with configurable retention and optional KMS encryption.
- **Private subnets are private** — no public IP auto-assignment; outbound access is through NAT only.
- **Explicit topology** — subnets are driven by per-AZ CIDR lists, so the address plan is visible in code rather than computed implicitly.
- **Fault-tolerant NAT by default** — one NAT gateway per AZ unless `single_nat_gateway` is set to trade resilience for cost.

## Usage

```hcl
module "vpc" {
  source = "github.com/<your-github-org>/terraform-module-registry//modules/vpc?ref=v1.0.0"

  name               = "platform"
  cidr_block         = "10.0.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b"]

  public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]

  tags = {
    Environment = "prod"
    Owner       = "platform"
  }
}
```

### Cost-optimized single NAT

```hcl
module "vpc" {
  source = "github.com/<your-github-org>/terraform-module-registry//modules/vpc?ref=v1.0.0"

  name               = "sandbox"
  cidr_block         = "10.20.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b"]

  public_subnet_cidrs  = ["10.20.0.0/24", "10.20.1.0/24"]
  private_subnet_cidrs = ["10.20.10.0/24", "10.20.11.0/24"]

  single_nat_gateway = true
}
```

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | `string` | — | Name prefix for the VPC and child resources. |
| `cidr_block` | `string` | — | Primary IPv4 CIDR (/16–/28). |
| `availability_zones` | `list(string)` | — | Zones to spread subnets across (1–6). |
| `public_subnet_cidrs` | `list(string)` | `[]` | Public subnet CIDRs, one per AZ in order. |
| `private_subnet_cidrs` | `list(string)` | `[]` | Private subnet CIDRs, one per AZ in order. |
| `enable_dns_support` | `bool` | `true` | Enable DNS resolution. |
| `enable_dns_hostnames` | `bool` | `true` | Assign public DNS hostnames. |
| `map_public_ip_on_launch` | `bool` | `false` | Auto-assign public IPs in public subnets. |
| `enable_nat_gateway` | `bool` | `true` | Provision NAT for private egress. |
| `single_nat_gateway` | `bool` | `false` | Share one NAT instead of one per AZ. |
| `enable_flow_logs` | `bool` | `true` | Send Flow Logs to CloudWatch. |
| `flow_log_retention_days` | `number` | `90` | Flow Logs retention. |
| `flow_log_kms_key_arn` | `string` | `null` | KMS key for the Flow Logs group. |
| `tags` | `map(string)` | `{}` | Tags applied to all resources. |

## Outputs

| Name | Description |
|------|-------------|
| `vpc_id` | VPC ID. |
| `vpc_arn` | VPC ARN. |
| `vpc_cidr_block` | VPC primary CIDR. |
| `public_subnet_ids` | Map of AZ → public subnet ID. |
| `private_subnet_ids` | Map of AZ → private subnet ID. |
| `public_subnet_id_list` | List of public subnet IDs. |
| `private_subnet_id_list` | List of private subnet IDs. |
| `internet_gateway_id` | Internet gateway ID (or null). |
| `nat_gateway_ids` | Map of AZ → NAT gateway ID. |
| `nat_gateway_public_ips` | Map of AZ → NAT public IP. |
| `public_route_table_id` | Public route table ID (or null). |
| `private_route_table_ids` | Map of key → private route table ID. |
| `flow_log_group_name` | Flow Logs group name (or null). |

## Examples

- [`examples/basic`](./examples/basic) — two-AZ VPC with public/private subnets and per-AZ NAT.
- [`examples/complete`](./examples/complete) — single-NAT cost profile with custom retention.
