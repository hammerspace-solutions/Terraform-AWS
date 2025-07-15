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
# modules/ecgroup/ecgroup_main.tf
#
# This file contains the main logic for the ECGroup module. It creates the
# EC2 instances, security group, and attached EBS volumes.
# -----------------------------------------------------------------------------

data "aws_ec2_instance_type_offering" "ecgroup" {
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

  processed_user_data = var.user_data != "" ? templatefile(var.user_data, {
    SSH_KEYS = join("\n", local.ssh_public_keys)
  }) : null

  resource_prefix = "${var.common_config.project_name}-ecgroup"
}

resource "aws_security_group" "this" {
  name        = "${local.resource_prefix}-sg"
  description = "ECGroup instance security group"
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

  tags = merge(var.common_config.tags, {
    Name    = "${local.resource_prefix}-sg"
    Project = var.common_config.project_name
  })
}

resource "aws_instance" "nodes" {
  count           = var.node_count
  placement_group = var.placement_group_name != "" ? var.placement_group_name : null
  ami             = var.ami
  instance_type   = var.instance_type
  subnet_id       = var.common_config.subnet_id
  key_name        = var.common_config.key_name
  user_data       = local.processed_user_data

  vpc_security_group_ids = [aws_security_group.this.id]

  root_block_device {
    volume_size           = var.boot_volume_size
    volume_type           = var.boot_volume_type
    delete_on_termination = true
  }

  # Define the metadata volume inline
  ebs_block_device {
    device_name           = "/dev/xvdz"
    volume_type           = var.metadata_ebs_type
    volume_size           = var.metadata_ebs_size
    iops                  = var.metadata_ebs_iops
    throughput            = var.metadata_ebs_throughput
    delete_on_termination = true
  }

  # Define the storage volumes inline using a dynamic block
  dynamic "ebs_block_device" {
    for_each = range(var.storage_ebs_count)
    content {
      device_name           = "/dev/xvd${local.device_letters[ebs_block_device.key]}"
      volume_type           = var.storage_ebs_type
      volume_size           = var.storage_ebs_size
      iops                  = var.storage_ebs_iops
      throughput            = var.storage_ebs_throughput
      delete_on_termination = true
    }
  }

  lifecycle {
    precondition {
      condition     = var.node_count >= 4
      error_message = "EC-Group requires at least 4 nodes, but only ${var.node_count} were specified."
    }
    precondition {
      condition     = var.storage_ebs_count <= 22
      error_message = "EC-Group nodes are limited to 22 storage volumes, but ${var.storage_ebs_count} were specified."
    }
    precondition {
      condition     = var.storage_ebs_count * var.node_count >= 8
      error_message = "EC-Group requires at least 8 storage volumes, but only ${var.storage_ebs_count * var.node_count} were specified."
    }
  }

  tags = merge(var.common_config.tags, {
    Name    = "${local.resource_prefix}-${count.index + 1}"
    Project = var.common_config.project_name
  })

  capacity_reservation_specification {
    capacity_reservation_target {
      capacity_reservation_id = var.capacity_reservation_id
    }
  }
}
