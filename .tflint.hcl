# tflint configuration for the module registry.
#
# The Terraform ruleset enforces language hygiene (documented variables/outputs,
# no unused declarations, consistent naming); the AWS ruleset checks provider
# resource arguments. Both run per module in CI.

config {
  # Modules are called with example inputs from their examples/ dirs; lint the
  # module sources themselves.
  call_module_type = "local"
  force            = false
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.35.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# Language hygiene.
rule "terraform_required_version" {
  enabled = true
}

rule "terraform_required_providers" {
  enabled = true
}

rule "terraform_unused_declarations" {
  enabled = true
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

rule "terraform_typed_variables" {
  enabled = true
}

rule "terraform_naming_convention" {
  enabled = true
}
