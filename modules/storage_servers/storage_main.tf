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
# modules/storage_servers/storage_main.tf
#
# This file contains the main logic for the Storage Servers module. It creates
# the EC2 instances, security group, and attached EBS volumes.
# -----------------------------------------------------------------------------

data "aws_ec2_instance_type_offering" "storage" {
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

data "aws_subnet" "selected" {
  id = var.common_config.subnet_id
}

# Get detail on the number of disks in the instance type

data "aws_ec2_instance_type" "nvme_disks" {
  instance_type = var.instance_type
}

# Partition aware so this works in commerical/Gov/China partitions

data "aws_partition" "current" {}

# Locals for drive creation and public key manipulation

locals {
  device_letters = [
    "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
    "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"
  ]

  ssh_public_keys = try(
    [
      for file in fileset(var.common_config.ssh_keys_dir, "*.pub") :
        trimspace(file("${var.common_config.ssh_keys_dir}/${file}"))
    ],
    []
  )

  # Grab the first (and only) storage-info block, or empty map if none

  instance_info = data.aws_ec2_instance_type.nvme_disks
  
  # Count the local NVMe disks on the instance

  nvme_count = try(
    sum([
      for disk in local.instance_info.instance_disks : disk.count
      if disk.type == "ssd"
    ]),
    0
  )
  
  storage_instance_type_is_available = length(data.aws_ec2_instance_type_offering.storage.instance_type) > 0

  processed_user_data = templatefile("${path.module}/scripts/user_data_universal.sh.tmpl", {
    SSH_KEYS    = join("\n", local.ssh_public_keys),
    TARGET_USER = var.target_user,
    TARGET_HOME = "/home/${var.target_user}",
    EBS_COUNT   = var.ebs_count + local.nvme_count,
    RAID_LEVEL  = var.raid_level,
    ALLOW_ROOT	= var.common_config.allow_root
  })

  resource_prefix = "${var.common_config.project_name}-storage"

  common_tags = merge(var.common_config.tags, {
    Project = var.common_config.project_name
  })
}

# Security Group

resource "aws_security_group" "storage" {
  name        = "${local.resource_prefix}-sg"
  description = "Storage instance security group"
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

resource "aws_instance" "storage_server" {
  count           = var.instance_count
  ami             = var.ami
  instance_type   = var.instance_type
  user_data       = local.processed_user_data

  placement_group             = var.common_config.placement_group_name
  subnet_id                   = var.common_config.subnet_id
  key_name                    = var.common_config.key_name

  vpc_security_group_ids = [aws_security_group.storage.id]
  iam_instance_profile = var.iam_profile_name
  
  # Put tags on the volumes

  volume_tags = merge(local.common_tags, {
    Name   = "${local.resource_prefix}-vol"
  })

  # Add this block here
  
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "optional"
    http_put_response_hop_limit = 2
  }
  
  # Create the boot disk
  
  root_block_device {
    volume_size           = var.boot_volume_size
    volume_type           = var.boot_volume_type
    delete_on_termination = true
  }

  # Define the data volumes inline using a dynamic block.
  # The `delete_on_termination` argument defaults to `true` here.

  dynamic "ebs_block_device" {
    for_each = range(var.ebs_count)
    content {
      device_name           = "/dev/xvd${local.device_letters[ebs_block_device.key]}"
      volume_type           = var.ebs_type
      volume_size           = var.ebs_size
      iops                  = var.ebs_iops
      throughput            = var.ebs_throughput
      delete_on_termination = true
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
      condition = (var.ebs_count + local.nvme_count) >= {
        "raid-0" = 2,
        "raid-5" = 3,
        "raid-6" = 4
      }[var.raid_level]

      error_message = "The selected RAID level (${var.raid_level}) requires at least ${lookup({ "raid-0" = 2, "raid-5" = 3, "raid-6" = 4 }, var.raid_level, 0)} total volumes, but only ${var.ebs_count} EBS and ${local.nvme_count} local NVMe volumes were specified."
    }
    precondition {
      condition     = local.storage_instance_type_is_available
      error_message = "ERROR: Instance type ${var.instance_type} for Storage is not available in AZ ${var.common_config.availability_zone}."
    }
  }

  tags = merge(var.common_config.tags, {
    Name    = "${local.resource_prefix}-${count.index + 1}"
    Project = var.common_config.project_name
  })
}
