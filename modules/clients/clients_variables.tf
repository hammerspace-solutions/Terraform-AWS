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
# modules/clients/clients_variables.tf
#
# This file defines all the input variables for the Clients module.
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

variable "iam_profile_name" {
  description = "The IAM profile to use for roles and permissions"
  type        = string
  default     = null
}

variable "iam_profile_group" {
  description = "The IAM group name"
  type        = string
  default     = null
}

variable "capacity_reservation_id" {
  description = "The ID of the On-Demand Capacity Reservation to target."
  type        = string
  default     = null
}

variable "ansible_key_name" {
  description = "The key pair name for SSH from Ansible controller to clients"
  type        = string
  default     = null
}

variable "ansible_sg_id" {
  description = "Security Group ID to allow SSH from Ansible controller"
  type        = string
  default     = null
}


# --- Client-specific variables (these remain) ---

variable "instance_count" {
  description = "Number of client instances"
  type        = number
}

variable "ami" {
  description = "AMI for client instances"
  type        = string
}

variable "instance_type" {
  description = "Instance type for clients"
  type        = string
}

variable "tier0" {
  description = "Tier0 enabled or not?"
  type       = bool
  default     = false
}

variable "tier0_type" {
  description = "RAID level to configure on client EBS volumes (raid-0, raid-5, or raid-6). Set to blank to skip RAID."
  type        = string
  default     = ""

  validation {
    condition     = contains(["raid-0", "raid-5", "raid-6"], var.tier0_type)
    error_message = "RAID level must be one of: raid-0, raid-5, or raid-6."
  }
}

variable "boot_volume_size" {
  description = "Root volume size (GB) for clients"
  type        = number
}

variable "boot_volume_type" {
  description = "Root volume type for clients"
  type        = string
}

variable "ebs_count" {
  description = "Number of extra EBS volumes per client"
  type        = number
}

variable "ebs_size" {
  description = "Size of each EBS volume (GB) for clients"
  type        = number
}

variable "ebs_type" {
  description = "Type of EBS volume for clients"
  type        = string
}

variable "ebs_throughput" {
  description = "Throughput for gp3 EBS volumes for clients (MB/s)"
  type        = number
  default     = null
}

variable "ebs_iops" {
  description = "IOPS for gp3/io1/io2 EBS volumes for clients"
  type        = number
  default     = null
}

variable "target_user" {
  description = "Default system user for client EC2s"
  type        = string
}
