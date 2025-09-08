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
# ansible variables.tf
#
# This file defines all the input ansible variables for the root module of the
# Terraform-AWS project.
# -----------------------------------------------------------------------------

# Ansible specific variables

variable "use_ssm_bootstrap" {
  description = "Use SSM to push keys and install Ansible controller"
  type        = bool
  default     = true
}

variable "authorized_keys" {
  description = "Authorized keys content to place into root and user accounts"
  type        = string
  default     = null
}

variable "ansible_instance_count" {
  description = "Number of ansible instances"
  type        = number
  default     = 1
}

variable "ansible_ami" {
  description = "AMI for Ansible instances"
  type        = string
}

variable "ansible_instance_type" {
  description = "Instance type for Ansible"
  type        = string
  default     = "m5n.8xlarge"
}

variable "ansible_boot_volume_size" {
  description = "Root volume size (GB) for Ansible"
  type        = number
  default     = 100
}

variable "ansible_boot_volume_type" {
  description = "Root volume type for Ansible"
  type        = string
  default     = "gp2"
}

variable "ansible_target_user" {
  description = "Default system user for Ansible EC2"
  type        = string
  default     = "ubuntu"
}
