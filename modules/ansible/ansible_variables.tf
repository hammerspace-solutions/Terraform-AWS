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
    assign_public_ip     = bool
    ssh_keys_dir         = string
    placement_group_name = string
  })
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

variable "user_data" {
  description = "Path to user data script for Ansible"
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

variable "admin_private_key" {
  description = "The private key material for the Ansible controller to use for bootstrapping."
  type        = string
  sensitive   = true
  default     = ""
}

# Other variables
variable "mgmt_ip" {
  description = "Hammerspace management IP address"
  type        = list(string)
  default     = []
}

variable "anvil_instances" {
  description = "Anvil instances details"
  type = list(object({
    type                       = string
    id                         = string
    arn                        = string
    private_ip                 = string
    public_ip                  = string
    key_name                   = string
    iam_profile                = string
    placement_group            = string
    all_private_ips_on_eni_set = set(string)
    floating_ip_candidate      = string
  }))
  default = []
}

variable "storage_instances" {
  description = "Storage instances details"
  type = list(object({
    id         = string
    private_ip = string
    name       = string
    public_ip  = string
  }))
  default = []
}

variable "volume_group_name" {
  description = "Volume group name for Anvil"
  type        = string
  default     = "vg-auto"
}

variable "share_name" {
  description = "Share name for Anvil"
  type        = string
  default     = ""
}
