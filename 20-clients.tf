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
# clients variables.tf
#
# This file defines all the input clients variables for the root module of the
# Terraform-AWS project.
# -----------------------------------------------------------------------------

# CLIENT-SPECIFIC VARIABLES (WITH clients_ PREFIX)

variable "clients_instance_count" {
  description = "Number of client instances"
  type        = number
}

variable "clients_tier0" {
  description = "Tier0 RAID config for clients. Blank ('') to skip, or 'raid-0', 'raid-5', 'raid-6'."
  type        = string
  default     = ""
}

variable "clients_ami" {
  description = "AMI for client instances"
  type        = string
}

variable "clients_instance_type" {
  description = "Instance type for clients"
  type        = string
}

variable "clients_boot_volume_size" {
  description = "Root volume size (GB) for clients"
  type        = number
  default     = 100
}

variable "clients_boot_volume_type" {
  description = "Root volume type for clients"
  type        = string
  default     = "gp2"
}

variable "clients_ebs_count" {
  description = "Number of extra EBS volumes per client"
  type        = number
  default     = 0
}

variable "clients_ebs_size" {
  description = "Size of each EBS volume (GB) for clients"
  type        = number
  default     = 1000
}

variable "clients_ebs_type" {
  description = "Type of EBS volume for clients"
  type        = string
  default     = "gp3"
}

variable "clients_ebs_throughput" {
  description = "Throughput for gp3 EBS volumes for clients (MB/s)"
  type        = number
  default     = null
}

variable "clients_ebs_iops" {
  description = "IOPS for gp3/io1/io2 EBS volumes for clients"
  type        = number
  default     = null
}

variable "clients_user_data" {
  description = "Path to user data script for clients"
  type        = string
  default     = ""
}

variable "clients_target_user" {
  description = "Default system user for client EC2s"
  type        = string
  default     = "ubuntu"
}
