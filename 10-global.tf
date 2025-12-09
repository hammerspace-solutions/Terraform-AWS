# Copyright (c) 2025 Hammerspace, Inc
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# -----------------------------------------------------------------------------
# global variables.tf
#
# This file defines all the global input variables for the root module of the
# Terraform-AWS project.
# -----------------------------------------------------------------------------

# Global variables (NO prefix)

variable "region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-west-2"
}

# Do we use an existing VPC or create a new one? The next two variables decide that
# question

variable "vpc_id" {
  description = "VPC ID for all resources"
  type        = string
  default     = null
}

variable "vpc_cidr" {
  description = "VPC CIDR Block"
  type        = string
  default     = null
}

# When defining Security Groups, what are the allowed CIDR that can address our instances?
# Define a list of those IP address ranges in this variable for locking down access to
# your instances.

variable "allowed_source_cidr_blocks" {
  description = "A list of additional IPv4 CIDR ranges to allow SSH and all other ingress traffic from (e.g., your corporate VPN range)."
  type        = list(string)
  default     = []
}

# Alias for private and public subnet(s). In MOST cases, we will not address a specific
# private subnet (either 1 or 2), but rather we want to address just private_subnet_id.
#
# The same is true for the public subnet...
#
# It is only with certain services like Amazon MQ or Aurora that we would want multiple
# private subnets

variable "private_subnet_id" {
  description = "Convenience alias for the primary private subnet"
  type        = string
  default     = null
}

variable "public_subnet_id" {
  description = "Convenience alias for the primary public subnet"
  type        = string
  default     = null
}

# Do we use an existing private or public subnet or create a new one. That question
# is defined in the next couple of variables

variable "private_subnet_1_id" {
  description = "Private Subnet 1 ID for resources"
  type        = string
  default     = null
}

variable "private_subnet_2_id" {
  description = "Private Subnet 2 ID for resources"
  type        = string
  default     = null
}

variable "public_subnet_1_id" {
  description = "The ID of the public subnet to use for instances requiring a public IP. Optional, but required if assign_public_ip is true."
  type        = string
  default     = null
}

variable "public_subnet_2_id" {
  description = "The ID of the public subnet to use for instances requiring a public IP. Optional, but required if assign_public_ip is true."
  type        = string
  default     = null
}

variable "assign_public_ip" {
  description = "If true, assigns a public IP address to all created EC2 instances. If false, only a private IP will be assigned."
  type        = bool
  default     = false
}

variable "private_subnet_1_cidr" {
  description = "Private Subnet-1 CIDR Block"
  type        = string
  default     = null
}

variable "subnet_1_az" {
  description = "Subnet-1 Availability Zone"
  type        = string
  default     = null
}

variable "private_subnet_2_cidr" {
  description = "Private Subnet-2 CIDR Block"
  type        = string
  default     = null
}

variable "subnet_2_az" {
  description = "Subnet-2 Availability Zone"
  type        = string
  default     = null
}

variable "public_subnet_1_cidr" {
  description = "Public Subnet-1 CIDR"
  type        = string
  default     = null
}

variable "public_subnet_2_cidr" {
  description = "Public Subnet-2 CIDR"
  type        = string
  default     = null
}

# Custom AMI's and their Owner ID's...

variable "custom_ami_owner_ids" {
  description = "A list of additional AWS Account IDs to search for AMIs. Use this if you are using private or community AMIs shared from other accounts."
  type        = list(string)
  default     = []
}

variable "key_name" {
  description = "SSH key pair name"
  type        = string
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}

variable "project_name" {
  description = "Project name for tagging and resource naming"
  type        = string
  default     = ""
  validation {
    condition     = var.project_name != ""
    error_message = "Project must have a name"
  }
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.project_name))
    error_message = "Project name can only contain letters, numbers, hyphens, or underscores"
  }
}

variable "ssh_keys_dir" {
  description = "Directory containing SSH public keys"
  type        = string
  default     = "./ssh_keys"
}

variable "allow_root" {
  description = "Allow root access to SSH"
  type        = bool
  default     = false
}

variable "deploy_components" {
  description = "Components to deploy. Valid values in the list are: \"all\", \"clients\", \"storage\", \"hammerspace\", \"ecgroup\", \"mq (amazon mq)\", \"aurora\"."
  type        = list(string)
  default     = ["all"]
  validation {
    condition = alltrue([
      for c in var.deploy_components : contains(["all", "clients", "storage", "hammerspace", "ecgroup", "mq", "aurora"], c)
    ])
    error_message = "Each item in deploy_components must be one of: \"all\", \"clients\", \"storage\", \"ecgroup\", \"hammerspace\", \"mq (amazon mq)\", or \"aurora\"."
  }
}

variable "capacity_reservation_create_timeout" {
  description = "The duration to wait for a capacity reservation to be fulfilled before timing out. Examples: '5m' for 5 minutes, '10m' for 10 minutes."
  type        = string
  default     = "5m"
}

variable "capacity_reservation_expiration" {
  description = "The amount of time (in minutes) before a capacity reservation is expired"
  type        = string
  default     = "10m"
}

variable "placement_group_name" {
  description = "Optional: The name of the placement group to create and launch instances into. If left blank, no placement group is used."
  type        = string
  default     = ""
}

variable "placement_group_strategy" {
  description = "The strategy to use for the placement group: cluster, spread, or partition."
  type        = string
  default     = "cluster"
  validation {
    condition     = contains(["cluster", "spread", "partition"], var.placement_group_strategy)
    error_message = "Allowed values for placement_group_strategy are: cluster, spread, or partition."
  }
}

variable "iam_admin_group_name" {
  description = "IAM admin group name for SSH access (can be existing group name or blank to create new)"
  type        = string
  default     = ""
}

variable "iam_profile_name" {
  description = "The name of an existing IAM Instance Profile to attach to instances. If left blank, a new one will be created with the necessary policies."
  type        = string
  default     = null
}

variable "iam_role_path" {
  description = "The IAM role path"
  type        = string
  default     = "/"
}

variable "iam_additional_policy_arns" {
  description = "A list of additional iam policies to implement"
  type        = list(string)
  default     = []
}

# Create a DNS if requested

variable "hosted_zone_name" {
  description = "Route 53 Private Hosted Zone Name"
  type        = string
  default     = ""
}

