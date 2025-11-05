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
# ansible configuration variables.tf
#
# This file defines all of the variables needed for ansible to configure shares,
# volume-groups, etc
# -----------------------------------------------------------------------------

variable "storage_vg_name" {
  description = "List of volume group names to create"
  type	      = list(string)
  default     = []
}

variable "storage_share_name" {
  description = "List of share names to create"
  type	      = list(string)
  default     = []
}

variable "ecgroup_vg_name" {
  description = "Volume Group created to store ECGroup volume"
  type	      = string
  default     = null
}

variable "ecgroup_share_name" {
  description = "Share name created to manage ECGroup volume(s)"
  type	      = string
  default     = null
}
d