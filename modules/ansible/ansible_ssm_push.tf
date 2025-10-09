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
# This file contains the logic to push the generated inventory.ini file to the
# Ansible instance on every 'terraform apply' run.
# -----------------------------------------------------------------------------

resource "time_static" "inventory_push_trigger" {
  # This resource's sole purpose is to get a new timestamp on every 'apply',
  # which we use to force the recreation of the SSM association below,
  # effectively triggering the inventory push.
}

resource "aws_ssm_document" "copy_inventory" {
  count = var.use_ssm_bootstrap ? 1 : 0

  name          = "${local.resource_prefix}-copy-inventory"
  document_type = "Command"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Copy the Ansible inventory file to the trigger directory on the Ansible controller."
    parameters = {
      InventoryContentB64 = { type = "String", description = "Base64 encoded content of the inventory.ini file" }
      TargetUser          = { type = "String", description = "The user that should own the inventory file" }
    }
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "copyInventory"
      inputs = {
        runCommand = [
          "# Ensure the trigger directory exists, making this command robust and idempotent.",
          "mkdir -p /var/ansible/trigger",
          "# Decode the inventory content from Base64 and write it to the trigger file.",
          "echo {{ InventoryContentB64 }} | base64 -d > /var/ansible/trigger/inventory.ini",
          "# Set the correct ownership and permissions on the file.",
          "chown {{ TargetUser }}:{{ TargetUser }} /var/ansible/trigger/inventory.ini",
          "chmod 0644 /var/ansible/trigger/inventory.ini"
        ]
      }
    }]
  })
}

resource "aws_ssm_association" "push_inventory_every_apply" {
  count = var.use_ssm_bootstrap ? var.instance_count : 0

  # By including the timestamp in the name, we force Terraform to create a new
  # association on every 'apply', which runs the command immediately.
  association_name = "PushInventory-${var.common_config.project_name}-${replace(time_static.inventory_push_trigger.rfc3339, ":", "-")}"
  name             = aws_ssm_document.copy_inventory[0].name

  targets {
    key    = "InstanceIds"
    values = [aws_instance.ansible[count.index].id]
  }

  parameters = {
    InventoryContentB64 = base64encode(local_file.ansible_inventory.content)
    TargetUser          = var.target_user
  }

  # This is the crucial dependency chain that ensures the correct order of operations.
  depends_on = [
    aws_ssm_association.ansible_bootstrap,
    # This is the corrected dependency.
    # It now correctly waits for the new polling resource to complete successfully.
    null_resource.wait_for_ssm_agent_polling
  ]
}
