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

variable "allowed_source_cidr_blocks" {
  description = "A list of additional IPv4 CIDR ranges to allow SSH and all other ingress traffic from (e.g., your corporate VPN range)."
  type        = list(string)
  default     = []
}

variable "public_subnet_id" {
  description = "The ID of the public subnet to use for instances requiring a public IP. Optional, but required if assign_public_ip is true."
  type        = string
  default     = ""
}

variable "assign_public_ip" {
  description = "If true, assigns a public IP address to all created EC2 instances. If false, only a private IP will be assigned."
  type        = bool
  default     = false
}

variable "custom_ami_owner_ids" {
  description = "A list of additional AWS Account IDs to search for AMIs. Use this if you are using private or community AMIs shared from other accounts."
  type        = list(string)
  default     = []
}

variable "vpc_id" {
  description = "VPC ID for all resources"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for resources"
  type        = string
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
}

variable "ssh_keys_dir" {
  description = "Directory containing SSH public keys"
  type        = string
  default     = "./ssh_keys"
}

variable "allow_root" {
  description = "Allow root access to SSH"
  type	      = bool
  default     = false
}

variable "deploy_components" {
  description = "Components to deploy. Valid values in the list are: \"all\", \"clients\", \"storage\", \"hammerspace\", \"ecgroup\", \"ansible\"."
  type        = list(string)
  default     = ["all"]
  validation {
    condition = alltrue([
      for c in var.deploy_components : contains(["all", "clients", "storage", "hammerspace", "ecgroup", "ansible"], c)
    ])
    error_message = "Each item in deploy_components must be one of: \"all\", \"ansible\", \"clients\", \"storage\", \"ecgroup\" or \"hammerspace\"."
  }
}

variable "capacity_reservation_create_timeout" {
  description = "The duration to wait for a capacity reservation to be fulfilled before timing out. Examples: '5m' for 5 minutes, '10m' for 10 minutes."
  type        = string
  default     = "5m"
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
