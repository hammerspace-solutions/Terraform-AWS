# iam-core

Creates a minimal EC2 instance **role** and **instance profile** with SSM access by default, optional CloudWatch Agent, and room for additional managed or inline policies.

### Inputs
- `project_name` (string): Name/Tag.
- `role_name` (string, default `hs-core`): Name suffix for role/profile.
- `enable_ssm` (bool, default `true`): Attach `AmazonSSMManagedInstanceCore`.
- `enable_cloudwatch_agent` (bool, default `true`): Attach `CloudWatchAgentServerPolicy`.
- `additional_managed_policy_arns` (list(string)): Extra AWS managed policy ARNs.
- `inline_policies` (map(string)): Map of policy-name => JSON policy document.

### Outputs
- `role_name`, `role_arn`, `instance_profile_name`, `instance_profile_arn`.

### Usage
```hcl
module "iam_core" {
source = "./modules/iam-core"
project_name = var.project_name
role_name = "hs-core"
enable_ssm = true
enable_cloudwatch_agent = true
additional_managed_policy_arns = []
inline_policies = {}
}

# Example consumption in an instance module
module "hammerspace" {
source = "./modules/hammerspace"
# ... your existing inputs
instance_profile_name = module.iam_core.instance_profile_name
}

## `modules/iam-core/variables.tf`
```hcl
variable "project_name" {
type = string
description = "Project name for tagging."
}

variable "role_name" {
type = string
default = "hs-core"
description = "Base name for IAM role and instance profile."
}

variable "enable_ssm" {
type = bool
default = true
description = "Attach AmazonSSMManagedInstanceCore managed policy."
}

variable "enable_cloudwatch_agent" {
type = bool
default = true
description = "Attach CloudWatchAgentServerPolicy managed policy."
}

variable "additional_managed_policy_arns" {
type = list(string)
default = []
description = "Additional managed policy ARNs to attach to the role."
}

variable "inline_policies" {
type = map(string)
default = {}
description = "Map of { policy_name = json } inline policies attached to the role."
}
