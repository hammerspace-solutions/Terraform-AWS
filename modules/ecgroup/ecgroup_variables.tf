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
# modules/ecgroup/ecgroup_variables.tf
#
# This file defines all the input variables for the ECGroup module.
# -----------------------------------------------------------------------------

variable "common_config" {
  description = "A map containing common configuration values like region, VPC, subnet, etc."
  type = object({
    region                      = string
    availability_zone           = string
    vpc_id                      = string
    subnet_id                   = string
    key_name                    = string
    tags                        = map(string)
    project_name                = string
    ssh_keys_dir                = string
    placement_group_name        = string
    allowed_source_cidr_blocks  = list(string)
  })
}

variable "capacity_reservation_id" {
  description = "The ID of the On-Demand Capacity Reservation to target."
  type        = string
  default     = null
}

variable "placement_group_name" {
  description = "Optional: The name of the placement group for the instances."
  type        = string
  default     = ""
}

# ECGroup specific variables
variable "instance_type" {
  description = "Instance type for ecgroup node"
  type        = string
}

variable "node_count" {
  description = "Number of ecgroup node instances"
  type        = number
}

variable "ami" {
  description = "AMI for ecgroup instances"
  type        = string
}

variable "boot_volume_size" {
  description = "Root volume size (GB) for ecgroup nodes"
  type        = number
}

variable "boot_volume_type" {
  description = "Root volume type for ecgroup nodes"
  type        = string
}

variable "metadata_ebs_size" {
  description = "Size of the EBS metadata volume (GB) for ecgroup nodes"
  type        = number
}

variable "metadata_ebs_type" {
  description = "Type of EBS metadata volume for ecgroup nodes"
  type        = string
}

variable "metadata_ebs_throughput" {
  description = "Throughput for metadata EBS volumes for ecgroup nodes (MB/s)"
  type        = number
  default     = null
}

variable "metadata_ebs_iops" {
  description = "IOPS for gp3/io1/io2 the metadata EBS volumes for ecgroup nodes"
  type        = number
  default     = null
}

variable "storage_ebs_count" {
  description = "Number of extra EBS volumes per ecgroup nodes"
  type        = number
}

variable "storage_ebs_size" {
  description = "Size of each EBS storage volume (GB) for ecgroup nodes"
  type        = number
}

variable "storage_ebs_type" {
  description = "Type of EBS storage volume for ecgroup nodes"
  type        = string
}

variable "storage_ebs_throughput" {
  description = "Throughput for each EBS storage volumes for ecgroup nodes (MB/s)"
  type        = number
  default     = null
}

variable "storage_ebs_iops" {
  description = "IOPS for gp3/io1/io2 each EBS storage volumes for ecgroup nodes"
  type        = number
  default     = null
}

variable "user_data" {
  description = "Path to user data script for ECGroup nodes"
  type        = string
}
