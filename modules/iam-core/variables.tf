variable "project_name" {
  type        = string
  description = "Project name for tagging."
}

variable "role_name" {
  type        = string
  default     = "hs-core"
  description = "Base name for IAM role and instance profile."
}

variable "enable_ssm" {
  type        = bool
  default     = true
  description = "Attach AmazonSSMManagedInstanceCore managed policy."
}

variable "enable_cloudwatch_agent" {
  type        = bool
  default     = true
  description = "Attach CloudWatchAgentServerPolicy managed policy."
}

variable "additional_managed_policy_arns" {
  type        = list(string)
  default     = []
  description = "Additional managed policy ARNs to attach to the role."
}

variable "inline_policies" {
  type        = map(string)
  default     = {}
  description = "Map of { policy_name = json } inline policies attached to the role."
}
