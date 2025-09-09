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
# modules/ansible/ansible_ssm_push.tf
#
# This file contains the SSM resources to push the generated inventory.ini
# to the Ansible controller instance.
# -----------------------------------------------------------------------------

resource "aws_ssm_document" "copy_inventory" {
  # Since we are in the module, we assume if the module is used, these resources are needed.
  # The count logic is handled by the root module's call to this module.
  name          = "${var.common_config.project_name}-copy-inventory-to-ansible"
  document_type = "Command"

  content = jsonencode({
    schemaVersion = "2.2",
    description   = "Copy Ansible inventory file to the trigger directory, passed as a parameter.",
    parameters = {
      "InventoryContentBase64" = {
        "type"        = "String",
        "description" = "(Required) The base64-encoded content of the inventory.ini file."
      }
    },
    mainSteps = [
      {
        action = "aws:runShellScript",
        name   = "copyInventory",
        inputs = {
          runCommand = [
	    "install -d -m 0755 /var/ansible/trigger",
            "echo '{{ InventoryContentBase64 }}' | base64 --decode > /var/ansible/trigger/inventory.ini",
            "chown root:root /var/ansible/trigger/inventory.ini",
            "chmod 644 /var/ansible/trigger/inventory.ini"
          ]
        }
      }
    ]
  })

  tags = merge(
    local.common_tags,
    { Name = "${var.common_config.project_name}-CopyInventory" }
  )
}

resource "time_static" "inventory_push_trigger" {
  # This resource's timestamp ensures it changes on every `terraform apply` run.
}

resource "aws_ssm_association" "push_inventory_every_apply" {
  name             = aws_ssm_document.copy_inventory.name
  association_name = "PushInventory-${var.common_config.project_name}-${replace(time_static.inventory_push_trigger.rfc3339, ":", "-")}"

  parameters = {
    # Reference the local_file resource created in inventory.tf
    InventoryContentBase64 = base64encode(local_file.ansible_inventory.content)
  }

  targets {
    key    = "InstanceIds"
    # We target the first instance created by this module.
    values = [aws_instance.ansible[0].id]
  }

  apply_only_at_cron_interval = false

  depends_on = [
    local_file.ansible_inventory,
    aws_instance.ansible,
    time_sleep.wait_for_ssm_agent,
    aws_ssm_association.ansible_bootstrap,
  ]
}
