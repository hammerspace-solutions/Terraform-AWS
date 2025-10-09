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
# AUTHORS OF COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# -----------------------------------------------------------------------------
# modules/ansible/inventory.tf
#
# This file generates the Ansible inventory based on the deployed nodes.
# -----------------------------------------------------------------------------

locals {
  # The template expects a flat list of nodes, so we parse the JSON input variable.
  all_nodes = jsondecode(var.target_nodes_json)

  # Filter the nodes for each group
  client_nodes  = [for n in local.all_nodes : n.private_ip if n.type == "client"]
  storage_nodes = [for n in local.all_nodes : n.private_ip if n.type == "storage_server"]
  ecgroup_nodes = [for n in local.all_nodes : n.private_ip if n.type == "ecgroup"]
  hammerspace_nodes = [for n in local.all_nodes : n.private_ip if n.type == "anvil" || n.type == "dsx"]
}

resource "local_file" "ansible_inventory" {
  # The file is created within the module directory.
  # Terraform will handle reading its content for the SSM push.
  filename = "${path.module}/scripts/inventory.ini"
  content  = templatefile("${path.module}/scripts/inventory.ini.tpl", {
    clients         = local.client_nodes
    storage_servers = local.storage_nodes
    ecgroup_nodes   = local.ecgroup_nodes
    hammerspace_nodes = local.hammerspace_nodes
  })
}
