variable "role_name" {
  description = "Name of the IAM role."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.role_name))
    error_message = "role_name must be 1-64 chars using the IAM name charset (alphanumerics and +=,.@_-)."
  }
}

variable "path" {
  description = "IAM path for the role."
  type        = string
  default     = "/"

  validation {
    condition     = can(regex("^/([a-zA-Z0-9+=,.@_-]+/)*$", var.path))
    error_message = "path must start and end with / (for example / or /service-roles/)."
  }
}

variable "description" {
  description = "Description of the role's purpose."
  type        = string
  default     = "Managed by terraform-module-registry."
}

variable "trusted_service_principals" {
  description = "AWS service principals allowed to assume the role (for example ecs-tasks.amazonaws.com)."
  type        = list(string)
  default     = []
}

variable "trusted_role_arns" {
  description = "IAM role/user ARNs allowed to assume the role."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.trusted_role_arns : can(regex("^arn:aws[a-zA-Z-]*:iam::", a))])
    error_message = "every trusted_role_arns entry must be a valid IAM ARN."
  }
}

variable "trusted_account_ids" {
  description = "AWS account IDs whose principals may assume the role (root-account trust)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for id in var.trusted_account_ids : can(regex("^[0-9]{12}$", id))])
    error_message = "every trusted_account_ids entry must be a 12-digit AWS account ID."
  }
}

variable "oidc_providers" {
  description = <<-EOT
    Federated OIDC trust entries. Each supports:
      provider_arn - ARN of the IAM OIDC provider
      audience_key - condition key for the audience claim (for example token.actions.githubusercontent.com:aud)
      audiences    - allowed audience values
      subject_key  - condition key for the subject claim
      subjects     - allowed subject values (StringLike, so wildcards are permitted)
  EOT
  type = list(object({
    provider_arn = string
    audience_key = string
    audiences    = list(string)
    subject_key  = optional(string, null)
    subjects     = optional(list(string), [])
  }))
  default = []
}

variable "require_mfa" {
  description = "Require MFA for principals assuming the role (applies to account/role-ARN trust)."
  type        = bool
  default     = false
}

variable "external_id" {
  description = "Optional ExternalId condition for cross-account trust (confused-deputy protection)."
  type        = string
  default     = null
}

variable "max_session_duration" {
  description = "Maximum session duration in seconds for the assumed role."
  type        = number
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "max_session_duration must be between 3600 and 43200 seconds."
  }
}

variable "managed_policy_arns" {
  description = "ARNs of managed policies to attach to the role."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.managed_policy_arns : can(regex("^arn:aws[a-zA-Z-]*:iam::", a))])
    error_message = "every managed_policy_arns entry must be a valid IAM policy ARN."
  }
}

variable "inline_policies" {
  description = "Map of inline policy name to a JSON policy document string."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for doc in values(var.inline_policies) : can(jsondecode(doc))])
    error_message = "every inline_policies value must be a valid JSON policy document."
  }
}

variable "permissions_boundary_arn" {
  description = "ARN of a permissions boundary policy to cap the role's effective permissions."
  type        = string
  default     = null

  validation {
    condition     = var.permissions_boundary_arn == null || can(regex("^arn:aws[a-zA-Z-]*:iam::", var.permissions_boundary_arn))
    error_message = "permissions_boundary_arn must be null or a valid IAM policy ARN."
  }
}

variable "force_detach_policies" {
  description = "Force-detach attached policies when the role is destroyed."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to the role."
  type        = map(string)
  default     = {}
}
