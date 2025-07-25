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

data "aws_ec2_instance_type_offering" "ansible" {
  filter {
    name   = "instance-type"
    values = [var.instance_type]
  }
  filter {
    name   = "location"
    values = [var.common_config.availability_zone]
  }
  location_type = "availability-zone"
}

locals {
  ssh_public_keys = try(
    [
      for file in fileset(var.common_config.ssh_keys_dir, "*.pub") :
        trimspace(file("${var.common_config.ssh_keys_dir}/${file}"))
    ],
    []
  )

  ansible_instance_type_is_available = length(data.aws_ec2_instance_type_offering.ansible.instance_type) > 0
  
  processed_user_data = var.user_data != "" ? templatefile(var.user_data, {
    TARGET_USER            = var.target_user,
    TARGET_HOME            = "/home/${var.target_user}",
    SSH_KEYS               = join("\n", local.ssh_public_keys),
    TARGET_NODES_JSON      = var.target_nodes_json,
    MGMT_IP                = length(var.mgmt_ip) > 0 ? var.mgmt_ip[0] : "",
    ANVIL_ID               = length(var.anvil_instances) > 0 ? var.anvil_instances[0].id : "",
    BASTION_INSTANCES	   = jsonencode(var.bastion_instances),
    CLIENT_INSTANCES	   = jsonencode(var.client_instances),
    STORAGE_INSTANCES      = jsonencode(var.storage_instances),
    VG_NAME                = var.volume_group_name,
    SHARE_NAME             = var.share_name,
    ECGROUP_INSTANCES      = join(" ", var.ecgroup_instances),
    ECGROUP_HOSTS          = length(var.ecgroup_nodes) > 0 ? var.ecgroup_nodes[0] : "",
    ECGROUP_NODES          = join(" ", var.ecgroup_nodes),
    ECGROUP_METADATA_ARRAY = var.ecgroup_metadata_array,
    ECGROUP_STORAGE_ARRAY  = var.ecgroup_storage_array
  }) : null

  resource_prefix = "${var.common_config.project_name}-ansible"

  common_tags = merge(var.common_config.tags, {
    Project = var.common_config.project_name
  })
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
    cidr_blocks = var.common_config.allowed_source_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name    = "${local.resource_prefix}-sg"
  })
}

# Build a network interface JUST in case we need a public IP

resource "aws_network_interface" "ansible_ni" {
  count	              = 1
  subnet_id 	      = var.assign_public_ip && var.public_subnet_id != null ? var.public_subnet_id : var.common_config.subnet_id
  security_groups     = [aws_security_group.ansible.id]
  tags		      = merge(local.common_tags, { Name = "${var.common_config.project_name}-Ansible" })
}

resource "aws_eip" "ansible" {
  count	 	      = var.assign_public_ip ? 1 : 0
  domain	      = "vpc"
  tags		      = merge(local.common_tags, { Name = "${var.common_config.project_name}-Ansible-EIP" })
}

resource "aws_eip_association" "ansible" {
  count	 	           = var.assign_public_ip ? 1 : 0
  network_interface_id     = aws_network_interface.ansible_ni[0].id
  allocation_id		   = aws_eip.ansible[0].id
}

# Launch EC2 Ansible instances

resource "aws_instance" "ansible" {
  count         = var.instance_count
  ami           = var.ami
  instance_type = var.instance_type
  user_data     = local.processed_user_data

  key_name        = var.common_config.key_name
  placement_group = var.common_config.placement_group_name
  
  # Connect the network interface with the instance

  network_interface {
    device_index	      = 0
    network_interface_id      = aws_network_interface.ansible_ni[0].id
  }

  # Create the boot disk
  
  root_block_device {
    volume_size               = var.boot_volume_size
    volume_type 	      = var.boot_volume_type
    delete_on_termination     = true
  }

  dynamic "capacity_reservation_specification" {
    for_each = var.capacity_reservation_id != null ? { only = { id = var.capacity_reservation_id } } : {}
    content {
      capacity_reservation_target {
        capacity_reservation_id = capacity_reservation_specification.value.id
      }
    }
  }

  lifecycle {
    precondition {
      condition     = !(var.assign_public_ip && var.public_subnet_id == null)
      error_message = "If 'assign_public_ip' is true for Ansible, 'public_subnet_id' must be provided."
    }
    precondition {
      condition     = local.ansible_instance_type_is_available
      error_message = "ERROR: Instance type ${var.instance_type} for the Ansible is not available in AZ ${var.common_config.availability_zone}."
    }
  }
  
  tags = merge(local.common_tags, {
    Name    = "${local.resource_prefix}-${count.index + 1}"
  })
}

# Use a null_resource to conditionally run provisioners. This resource
# does nothing by itself, but allows us to use `count` to control whether
# the provisioners inside it are executed.

resource "null_resource" "key_provisioner" {
  # Only create this resource (and run its provisioners) if a key path is provided.
  count = var.admin_private_key_path != "" ? var.instance_count : 0

  # This trigger ensures the provisioner runs after the instance is created.

  triggers = {
    instance_id = aws_instance.ansible[count.index].id
  }

  # First provisioner copies the key file.

  provisioner "file" {
    source      = var.admin_private_key_path
    destination = "/home/${var.target_user}/.ssh/ansible_admin_key"

    connection {
      type        = "ssh"
      user        = var.target_user
      # The key used for the initial connection is the main one for the instance.
      private_key = file(var.admin_private_key_path)
      host        = var.assign_public_ip ? aws_instance.ansible[count.index].public_ip : aws_instance.ansible[count.index].private_ip
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
      host        = var.assign_public_ip ? aws_instance.ansible[count.index].public_ip : aws_instance.ansible[count.index].private_ip
    }
  }
}
