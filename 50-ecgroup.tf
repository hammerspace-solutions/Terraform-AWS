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
# ecgroup variables.tf
#
# This file defines all the input ecgroup variables for the root module of the
# Terraform-AWS project.
# -----------------------------------------------------------------------------

# ECGroup specific variables

variable "ecgroup_instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "m6i.16xlarge"
}

variable "ecgroup_node_count" {
  description = "Number of EC2 nodes to create"
  type        = number
  default     = 4
  validation {
    condition     = var.ecgroup_node_count >= 4 && var.ecgroup_node_count <= 16
    error_message = "ECGroup nodes must be between 4 and 16"
  }
}

variable "ecgroup_boot_volume_size" {
  description = "Root volume size (GB) for ecgroup nodes"
  type        = number
  default     = 100
}

variable "ecgroup_boot_volume_type" {
  description = "Root volume type for ecgroup nodes"
  type        = string
  default     = "gp2"
}

variable "ecgroup_metadata_volume_size" {
  description = "Size of the ecgroup metadata EBS volume in GiB"
  type        = number
  default     = 4096
}

variable "ecgroup_metadata_volume_type" {
  description = "Type of EBS metadata volume for ecgroup nodes"
  type        = string
  default     = "io2"
}

variable "ecgroup_metadata_volume_throughput" {
  description = "Throughput for metadata EBS volumes for ecgroup nodes (MB/s)"
  type        = number
  default     = null
}

variable "ecgroup_metadata_volume_iops" {
  description = "IOPS for gp3/io1/io2 the metadata EBS volumes for ecgroup nodes"
  type        = number
  default     = null
}

variable "ecgroup_storage_volume_count" {
  description = "Number of ecgroup storage volumes to attach to each node"
  type        = number
  default     = 4
}

variable "ecgroup_storage_volume_size" {
  description = "Size of each EBS storage volume (GB) for ecgroup nodes"
  type        = number
  default     = 4096
}

variable "ecgroup_storage_volume_type" {
  description = "Type of EBS storage volume for ecgroup nodes"
  type        = string
  default     = "gp3"
}

variable "ecgroup_storage_volume_throughput" {
  description = "Throughput for each EBS storage volumes for ecgroup nodes (MB/s)"
  type        = number
  default     = null
}

variable "ecgroup_storage_volume_iops" {
  description = "IOPS for gp3/io1/io2 each EBS storage volumes for ecgroup nodes"
  type        = number
  default     = null
}

variable "ecgroup_user_data" {
  description = "Path to user data script for ECGroup"
  type = string
  default = "./templates/ecgroup_node.sh.tmpl"
}
