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

variable "config_ansible" {
  description = "Nested structure passed to Ansible. Set to null to disable."
  type = object({
    allow_root           = bool
    ecgroup_volume_group = optional(string)
    ecgroup_share_name   = optional(string)
    volume_groups = map(object({
      volumes    = list(string)
      add_groups = optional(list(string), [])
      share      = string
    }))
  })
  default  = null
  nullable = true

  validation {
    # Pass (true) if any of these are true:
    # - config_ansible is null (nothing to validate)
    # - we're NOT deploying both storage & hammerspace
    # - storage_instance_count is not a positive known number yet
    # Otherwise, enforce the structure and index bounds.
    condition = (
      var.config_ansible == null
      || length(setintersection(toset(var.deploy_components), toset(["storage", "hammerspace"]))) != 2
      || !try(var.storage_instance_count > 0, false)
      || (
        length(var.config_ansible.volume_groups) > 0
        && alltrue([
          for vg in values(var.config_ansible.volume_groups) :
          length(vg.volumes) > 0
        ])
        && alltrue([
          for vg in values(var.config_ansible.volume_groups) :
          alltrue([
            for v in vg.volumes :
              can(tonumber(v))                                  # numeric string
              && tonumber(v) >= 1                               # 1-based index
              && tonumber(v) <= var.storage_instance_count      # within bounds
          ])
        ])
      )
    )

    error_message = "When deploying both 'storage' and 'hammerspace': if config_ansible is provided, volume_groups must be non-empty, each group must have at least one volume, and all volume indexes must be numeric and between 1 and storage_instance_count."
  }
}
