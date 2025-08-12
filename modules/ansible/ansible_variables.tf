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

variable "admin_private_key_path" {
  description = "The local path to the private key for the Ansible controller"
  type        = string
  sensitive   = true
  default     = ""
}

variable "admin_public_key_path" {
  description = "The local path to the public key for the Ansible controller"
  type        = string
  sensitive   = true
  default     = ""
}
