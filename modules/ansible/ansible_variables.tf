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
# modules/ansible/ansible_variables.tf
#
# This file defines all the input variables for the Ansible module.
# -----------------------------------------------------------------------------

variable "common_config" {
  description = "A map containing common configuration values like region, VPC, subnet, etc."
  type = object({
    region               = string
    availability_zone    = string
    vpc_id               = string
    subnet_id            = string
    key_name             = string
    tags                 = map(string)
    project_name         = string
    ssh_keys_dir         = string
    allow_root		 = bool
    placement_group_name = string
    allowed_source_cidr_blocks = list(string)
  })
}

variable "iam_profile_name" {
  description = "The IAM profile to use for roles and permissions"
  type	      = string
  default     = null
}

variable "iam_profile_group" {
  description = "The IAM group name"
  type	      = string
  default     = null
}

variable "public_subnet_id" {
  description = "The ID of the public subnet where the ansible instance will be launched. Required if assign_public_ip is true."
  type	      = string
  default     = null
}

variable "assign_public_ip" {
  description = "Assign a public IP to this host"
  type	      = bool
  default     = false
}

variable "capacity_reservation_id" {
  description = "The ID of the On-Demand Capacity Reservation to target."
  type	      = string
  default     = null
}

# Ansible specific variables

variable "instance_count" {
  description = "Number of Ansible instances"
  type        = number
}

variable "ami" {
  description = "AMI for Ansible instances"
  type        = string
}

variable "instance_type" {
  description = "Instance type for Ansible"
  type        = string
}

variable "boot_volume_size" {
  description = "Root volume size (GB) for Ansible"
  type        = number
}

variable "boot_volume_type" {
  description = "Root volume type for Ansible"
  type        = string
}

variable "target_user" {
  description = "Default system user for Ansible EC2"
  type        = string
}

variable "target_nodes_json" {
  description = "A JSON-encoded string of all client and storage nodes for Ansible to configure."
  type        = string
  default     = "[]"
}

# Turn on SSM bootstrap (set false to keep old SSH provisioners)

variable "use_ssm_bootstrap" {
  description = "Use SSM to push keys and install the Ansible controller on the Ansible host"
  type        = bool
  default     = true
}

# Authorized keys content to install for both root and ansible user.
# If null, we will read ${path.module}/files/authorized_keys

variable "authorized_keys" {
  description = "Authorized keys content to place into both root and user accounts"
  type        = string
  default     = null
  sensitive   = true
  validation {
    condition = var.authorized_keys != null || length(fileset(path.root, "ssh_keys/*.pub")) > 0
    error_message = "Provide var.authorized_keys or place one or more *.pub files under ssh_keys/."
  }
}

variable "ssm_bootstrap_delay" {
  description = "Time to wait for SSM Agent to come alive"
  type	      = string
  default     = "30s"
}

variable "ssm_bootstrap_retries" {
  description = "The number of times to retry checking for the SSM agent before failing."
  type	      = number
  default     = 4 # Results in a total default wait of 4 * 30s = 120s
}

variable "ssm_association_schedule" {
  description = "State Manager schedule for bootstrap retries"
  type	      = string
  default     = null # was THIS: "rate(30 minutes)"
}

variable "ansible_ssh_public_key" {
  description = "OpenSSH public key for controller (e.g. ssh-ed25519 AAA...)"
  type        = string
}

variable "ansible_private_key_secret_arn" {
  description = "Secrets Manager ARN holding the controller's private key"
  type        = string
}

variable "ansible_controller_cidr" {
  description = "CIDR allowed to SSH to targets (fallback)"
  type        = string
  default     = null
}


