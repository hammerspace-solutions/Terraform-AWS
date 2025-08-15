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
# modules/clients/clients_main.tf
#
# This file contains the main logic for the Clients module. It creates the
# EC2 instances, security group, EBS volumes, and attachments.
# -----------------------------------------------------------------------------

# Make sure the instance type is available in this availability zone

data "aws_ec2_instance_type_offering" "clients" {
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

# Get detail on the number of disks in the instance type

data "aws_ec2_instance_type" "nvme_disks" {
  instance_type = var.instance_type
}

locals {
  device_letters = [
    "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
    "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"
  ]

  # root user and home... Needed for template script

  root_user = "root"
  root_home = "/${local.root_user}"
  
  # Grab the first (and only) storage‐info block, or empty map if none
  
  instance_info = data.aws_ec2_instance_type.nvme_disks

  # Calculate NVMe drive count (0 if no instance storage)

  nvme_count = try(
    sum([
      for disk in local.instance_info.instance_disks : disk.count
      if disk.type == "ssd"
    ]),
    0
  )
  
  ssh_public_keys = try(
    [
      for file in fileset(var.common_config.ssh_keys_dir, "*.pub") :
        trimspace(file("${var.common_config.ssh_keys_dir}/${file}"))
    ],
    []
  )

  client_instance_type_is_available = length(data.aws_ec2_instance_type_offering.clients.instance_type) > 0

  # Process the bash shell template
  
  processed_user_data = templatefile("${path.module}/scripts/user_data_${var.target_user}.sh.tmpl", {
    TARGET_USER	      = var.target_user,
    TARGET_HOME	      = "/home/${var.target_user}",
    SSH_KEYS   	      = join("\n", local.ssh_public_keys),
    TIER0	      = var.tier0,
    TIER0_TYPE	      = var.tier0_type, 
    ALLOW_ROOT	      = var.common_config.allow_root,
    ROOT_USER	      = local.root_user,
    ROOT_HOME	      = local.root_home
  })

  resource_prefix = "${var.common_config.project_name}-client"

  common_tags = merge(var.common_config.tags, {
    Project = var.common_config.project_name
  })
}

# Security group for client instances

resource "aws_security_group" "client" {
  name        = "${local.resource_prefix}-sg"
  description = "Client instance security group"
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

# Launch EC2 client instances

resource "aws_instance" "clients" {
  count         = var.instance_count
  ami           = var.ami
  instance_type = var.instance_type
  user_data     = local.processed_user_data

  # Use values from the common_config object
  subnet_id                   = var.common_config.subnet_id
  key_name                    = var.common_config.key_name
  placement_group             = var.common_config.placement_group_name

  vpc_security_group_ids = [aws_security_group.client.id]

  # Put tags on the volumes

  volume_tags = merge(local.common_tags, {
    Name   = "${local.resource_prefix}-vol"
  })

  # Create the boot disk
  
  root_block_device {
    volume_size           = var.boot_volume_size
    volume_type           = var.boot_volume_type
    delete_on_termination = true
  }

  # Define the data volumes inline using a dynamic block.
  # The `delete_on_termination` argument defaults to `true` here, which is
  # exactly what you want.

  dynamic "ebs_block_device" {
    for_each = range(var.ebs_count)
    content {
      device_name = "/dev/xvd${local.device_letters[ebs_block_device.key]}"
      volume_type = var.ebs_type
      volume_size = var.ebs_size
      iops        = var.ebs_iops
      throughput  = var.ebs_throughput
      # delete_on_termination = true # This is the default and can be omitted
    }
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
      condition     = local.client_instance_type_is_available
      error_message = "ERROR: Instance type ${var.instance_type} for Clients is not available in AZ ${var.common_config.availability_zone}."
    }
    
    precondition {
      condition = (
        var.tier0 == "" ||  # if no tier0 requested, skip the check
	local.nvme_count >= lookup({
          "raid-0" = 2,
          "raid-5" = 3,
	  "raid-6" = 4,
        }, var.tier0)
      )

      error_message = "Insufficient total devices for tier0: if set, 'raid-0' needs ≥2, 'raid-5' needs ≥3, 'raid-6' needs ≥4."
    }
  }
  
  tags = merge(local.common_tags, {
    Name    = "${local.resource_prefix}-${count.index + 1}"
  })
}

