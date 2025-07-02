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
    assign_public_ip     = bool
    ssh_keys_dir         = string
    placement_group_name = string
  })
}

variable "capacity_reservation_id" {
  description = "The ID of the On-Demand Capacity Reservation to target."
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

variable "user_data" {
  description = "Path to user data script for clients"
  type        = string
}

variable "target_user" {
  description = "Default system user for client EC2s"
  type        = string
}
