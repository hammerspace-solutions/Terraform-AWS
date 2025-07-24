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
# bastion variables.tf
#
# This file defines all the input variables for the bastion client in the
# root module of the Terraform-AWS project.
# -----------------------------------------------------------------------------

# BASTION-SPECIFIC VARIABLES (WITH bastion_ PREFIX)

variable "bastion_instance_count" {
  description = "Number of bastion client instances"
  type        = number
  default     = 1
}

variable "bastion_ami" {
  description = "AMI for the bastion client instances"
  type        = string
}

variable "bastion_instance_type" {
  description = "Instance type for the bastion client"
  type        = string
}

variable "bastion_boot_volume_size" {
  description = "Root volume size (GB) for the bastion client"
  type        = number
  default     = 100
}

variable "bastion_boot_volume_type" {
  description = "Root volume type for the bastion client"
  type        = string
  default     = "gp2"
}

variable "bastion_user_data" {
  description = "Path to user data script for bastion client"
  type	      = string
  default     = "./templates/bastion_config_ubuntu.sh"
}

variable "bastion_target_user" {
  description = "Default system user for bastion EC2s"
  type        = string
  default     = "ubuntu"
}
