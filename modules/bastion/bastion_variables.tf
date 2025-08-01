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
# modules/bastion/bastion_variables.tf
#
# This file defines all the input variables for the Bastion client module.
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
    placement_group_name = string
    allowed_source_cidr_blocks = list(string)
  })
}

variable "public_subnet_id" {
  description = "The ID of the public subnet where the bastion instance will be launched. Required if assign_public_ip is true."
  type        = string
  default     = null
}

variable "assign_public_ip" {
  description = "Assign a public IP to this host"
  type        = bool
  default     = false
}

variable "capacity_reservation_id" {
  description = "The ID of the On-Demand Capacity Reservation to target."
  type        = string
  default     = null
}

# --- Bastion-specific variables (these remain) ---

variable "instance_count" {
  description = "Number of bastion client instances"
  type        = number
}

variable "ami" {
  description = "AMI for the bastion client instances"
  type        = string
}

variable "instance_type" {
  description = "Instance type for the bastion client"
  type        = string
}

variable "boot_volume_size" {
  description = "Root volume size (GB) for the bastion client"
  type        = number
}

variable "boot_volume_type" {
  description = "Root volume type for the bastion client"
  type        = string
}

variable "user_data" {
  description = "Path to user data script for the bastion client"
  type	      = string
}

variable "target_user" {
  description = "Default system user for the bastion client EC2s"
  type        = string
}
