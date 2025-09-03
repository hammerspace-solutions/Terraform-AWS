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
# hammerspace variables.tf
#
# This file defines all the input hammerspace variables for the root module
# of the Terraform-AWS project.
# -----------------------------------------------------------------------------

# Hammerspace-specific variables

variable "hammerspace_ami" {
  description = "AMI ID for Hammerspace instances"
  type        = string
  default     = ""
}

variable "hammerspace_anvil_security_group_id" {
  description = "Optional: An existing security group ID to use for the Anvil nodes."
  type        = string
  default     = ""
}

variable "hammerspace_dsx_security_group_id" {
  description = "Optional: An existing security group ID to use for the DSX nodes."
  type        = string
  default     = ""
}

variable "hammerspace_anvil_count" {
  description = "Number of Anvil instances to deploy (0=none, 1=standalone, 2=HA)"
  type        = number
  default     = 0
  validation {
    condition     = var.hammerspace_anvil_count >= 0 && var.hammerspace_anvil_count <= 2
    error_message = "anvil count must be 0, 1 (standalone), or 2 (HA)"
  }
}

variable "hammerspace_sa_anvil_destruction" {
  description = "A safety switch to allow the destruction of a standalone Anvil. Must be set to true for 'terraform destroy' to succeed on a 1-Anvil deployment."
  type        = bool
  default     = false
}

variable "hammerspace_anvil_instance_type" {
  description = "Instance type for Anvil metadata server"
  type        = string
  default     = "m5zn.12xlarge"
}

variable "hammerspace_dsx_instance_type" {
  description = "Instance type for DSX nodes"
  type        = string
  default     = "m5.xlarge"
}

variable "hammerspace_dsx_count" {
  description = "Number of DSX instances"
  type        = number
  default     = 1
}

variable "hammerspace_anvil_meta_disk_size" {
  description = "Metadata disk size in GB for Anvil"
  type        = number
  default     = 1000
}

variable "hammerspace_anvil_meta_disk_type" {
  description = "Type of EBS volume for Anvil metadata disk (e.g., gp3, io2)"
  type        = string
  default     = "gp3"
}

variable "hammerspace_anvil_meta_disk_throughput" {
  description = "Throughput for gp3 EBS volumes for the Anvil metadata disk (MiB/s)"
  type        = number
  default     = null
}

variable "hammerspace_anvil_meta_disk_iops" {
  description = "IOPS for gp3/io1/io2 EBS volumes for the Anvil metadata disk"
  type        = number
  default     = null
}

variable "hammerspace_dsx_ebs_size" {
  description = "Size of each EBS Data volume per DSX node in GB"
  type        = number
  default     = 200
}

variable "hammerspace_dsx_ebs_type" {
  description = "Type of each EBS Data volume for DSX (e.g., gp3, io2)"
  type        = string
  default     = "gp3"
}

variable "hammerspace_dsx_ebs_iops" {
  description = "IOPS for each EBS Data volume for DSX"
  type        = number
  default     = null
}

variable "hammerspace_dsx_ebs_throughput" {
  description = "Throughput for each EBS Data volume for DSX (MiB/s)"
  type        = number
  default     = null
}

variable "hammerspace_dsx_ebs_count" {
  description = "Number of data EBS volumes to attach to each DSX instance."
  type        = number
  default     = 1
}

variable "hammerspace_dsx_add_vols" {
  description = "Add non-boot EBS volumes as Hammerspace storage volumes"
  type        = bool
  default     = true
}
