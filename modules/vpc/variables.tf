variable "name" {
  description = "Name prefix applied to the VPC and all child resources."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,62}$", var.name))
    error_message = "name must be 2-63 chars, start with a letter, and contain only letters, digits, and hyphens."
  }
}

variable "cidr_block" {
  description = "Primary IPv4 CIDR block for the VPC."
  type        = string

  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "cidr_block must be a valid IPv4 CIDR (for example 10.0.0.0/16)."
  }

  validation {
    condition     = tonumber(split("/", var.cidr_block)[1]) >= 16 && tonumber(split("/", var.cidr_block)[1]) <= 28
    error_message = "cidr_block prefix length must be between /16 and /28."
  }
}

variable "availability_zones" {
  description = "Availability zones to spread subnets across. Determines subnet count."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 1 && length(var.availability_zones) <= 6
    error_message = "availability_zones must contain between 1 and 6 zones."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets, one per availability zone (in order). Empty disables public subnets."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.public_subnet_cidrs : can(cidrhost(c, 0))])
    error_message = "every public_subnet_cidrs entry must be a valid IPv4 CIDR."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets, one per availability zone (in order). Empty disables private subnets."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.private_subnet_cidrs : can(cidrhost(c, 0))])
    error_message = "every private_subnet_cidrs entry must be a valid IPv4 CIDR."
  }
}

variable "enable_dns_support" {
  description = "Enable DNS resolution in the VPC."
  type        = bool
  default     = true
}

variable "enable_dns_hostnames" {
  description = "Assign public DNS hostnames to instances with public IPs."
  type        = bool
  default     = true
}

variable "map_public_ip_on_launch" {
  description = "Auto-assign public IPs to instances launched in public subnets."
  type        = bool
  default     = false
}

variable "enable_nat_gateway" {
  description = "Provision NAT gateway(s) so private subnets get outbound internet access."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use one shared NAT gateway instead of one per availability zone. Cheaper, but not zone-fault-tolerant."
  type        = bool
  default     = false
}

variable "enable_flow_logs" {
  description = "Send VPC Flow Logs to a KMS-encrypted CloudWatch Logs group."
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "Retention for the Flow Logs log group, in days."
  type        = number
  default     = 90

  validation {
    condition = contains(
      [0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653],
      var.flow_log_retention_days
    )
    error_message = "flow_log_retention_days must be a value CloudWatch Logs accepts (for example 30, 90, 365)."
  }
}

variable "flow_log_kms_key_arn" {
  description = "KMS key ARN encrypting the Flow Logs group. When null, the log group uses the default CloudWatch encryption."
  type        = string
  default     = null

  validation {
    condition     = var.flow_log_kms_key_arn == null || can(regex("^arn:aws[a-zA-Z-]*:kms:", var.flow_log_kms_key_arn))
    error_message = "flow_log_kms_key_arn must be null or a valid KMS key ARN."
  }
}

variable "tags" {
  description = "Tags applied to every resource created by the module."
  type        = map(string)
  default     = {}
}
