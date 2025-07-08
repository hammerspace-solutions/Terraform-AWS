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
# modules/ansible/ansible_main.tf
#
# This file contains the main logic for the Ansible module. It creates the
# EC2 instance, security group, and processes the user data script.
# -----------------------------------------------------------------------------

locals {
  ssh_public_keys = try(
    [
      for file in fileset(var.common_config.ssh_keys_dir, "*.pub") :
        trimspace(file("${var.common_config.ssh_keys_dir}/${file}"))
    ],
    []
  )

  processed_user_data = var.user_data != "" ? templatefile(var.user_data, {
    TARGET_USER       = var.target_user
    TARGET_HOME       = "/home/${var.target_user}"
    SSH_KEYS          = join("\n", local.ssh_public_keys)
    TARGET_NODES_JSON = var.target_nodes_json
    MGMT_IP           = length(var.mgmt_ip) > 0 ? var.mgmt_ip[0] : null
    ANVIL_ID          = length(var.anvil_instances) > 0 ? var.anvil_instances[0].id : null
    STORAGE_INSTANCES = jsonencode(var.storage_instances)
    VG_NAME           = var.volume_group_name
    SHARE_NAME        = var.share_name
  }) : null

  resource_prefix = "${var.common_config.project_name}-ansible"
}

# Security group for ansible instances
resource "aws_security_group" "ansible" {
  name        = "${local.resource_prefix}-sg"
  description = "Ansible instance security group"
  vpc_id      = var.common_config.vpc_id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_config.tags, {
    Name    = "${local.resource_prefix}-sg"
    Project = var.common_config.project_name
  })
}

# Launch EC2 Ansible instances
resource "aws_instance" "this" {
  count         = var.instance_count
  ami           = var.ami
  instance_type = var.instance_type
  user_data     = local.processed_user_data

  subnet_id                   = var.common_config.subnet_id
  key_name                    = var.common_config.key_name
  associate_public_ip_address = var.common_config.assign_public_ip

  vpc_security_group_ids = [aws_security_group.ansible.id]

  root_block_device {
    volume_size = var.boot_volume_size
    volume_type = var.boot_volume_type
  }

  tags = merge(var.common_config.tags, {
    Name    = "${local.resource_prefix}-${count.index + 1}"
    Project = var.common_config.project_name
  })
}

# --- THIS IS THE FIX ---
# Use a null_resource to conditionally run provisioners. This resource
# does nothing by itself, but allows us to use `count` to control whether
# the provisioners inside it are executed.
resource "null_resource" "key_provisioner" {
  # Only create this resource (and run its provisioners) if a key path is provided.
  count = var.admin_private_key_path != "" ? var.instance_count : 0

  # This trigger ensures the provisioner runs after the instance is created.
  triggers = {
    instance_id = aws_instance.this[count.index].id
  }

  # First provisioner copies the key file.
  provisioner "file" {
    source      = var.admin_private_key_path
    destination = "/home/${var.target_user}/.ssh/ansible_admin_key"

    connection {
      type        = "ssh"
      user        = var.target_user
      # Use the *main* key (from var.common_config.key_name) for the initial connection.
      private_key = file(var.admin_private_key_path)
      host        = var.common_config.assign_public_ip ? aws_instance.this[count.index].public_ip : aws_instance.this[count.index].private_ip
    }
  }

  # Second provisioner sets the correct permissions on the uploaded key.
  provisioner "remote-exec" {
    inline = [
      "sudo chmod 600 /home/${var.target_user}/.ssh/ansible_admin_key",
      "sudo chown ${var.target_user}:${var.target_user} /home/${var.target_user}/.ssh/ansible_admin_key"
    ]

    connection {
      type        = "ssh"
      user        = var.target_user
      private_key = file(var.admin_private_key_path)
      host        = var.common_config.assign_public_ip ? aws_instance.this[count.index].public_ip : aws_instance.this[count.index].private_ip
    }
  }
}
