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
# storage server variables.tf
#
# This file defines all the input storage server variables for the root module
# of the Terraform-AWS project.
# -----------------------------------------------------------------------------

# STORAGE-SPECIFIC VARIABLES (WITH storage_ PREFIX)

variable "storage_instance_count" {
  description = "Number of storage instances"
  type        = number
  default     = 0
}

variable "storage_ami" {
  description = "AMI for storage instances"
  type        = string
}

variable "storage_instance_type" {
  description = "Instance type for storage"
  type        = string
}

variable "storage_boot_volume_size" {
  description = "Root volume size (GB) for storage"
  type        = number
  default     = 100
}

variable "storage_boot_volume_type" {
  description = "Root volume type for storage"
  type        = string
  default     = "gp2"
}

variable "storage_ebs_count" {
  description = "Number of extra EBS volumes per storage"
  type        = number
  default     = 0
}

variable "storage_ebs_size" {
  description = "Size of each EBS volume (GB) for storage"
  type        = number
  default     = 1000
}

variable "storage_ebs_type" {
  description = "Type of EBS volume for storage"
  type        = string
  default     = "gp3"
}

variable "storage_ebs_throughput" {
  description = "Throughput for gp3 EBS volumes for storage (MB/s)"
  type        = number
  default     = null
}

variable "storage_ebs_iops" {
  description = "IOPS for gp3/io1/io2 EBS volumes for storage"
  type        = number
  default     = null
}

variable "storage_target_user" {
  description = "Default system user for storage EC2s"
  type        = string
  default     = "ubuntu"
}

variable "storage_raid_level" {
  description = "RAID level to configure (raid-0, raid-5, or raid-6)"
  type        = string
  default     = "raid-5"

  validation {
    condition     = contains(["raid-0", "raid-5", "raid-6"], var.storage_raid_level)
    error_message = "RAID level must be one of: raid-0, raid-5, or raid-6"
  }
}

variable "storage_vg_name" {
  description = "Name of the volume group for Hammerspace configuration"
  type        = string
  default     = "storage-vg"  # Fallback if not provided
}

variable "storage_share_name" {
  description = "Name of the share for Hammerspace configuration"
  type        = string
  default     = "storage-share"  # Fallback if not provided
}
