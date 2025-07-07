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
# the EC2 instances, security group, EBS volumes, and attachments.
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

  storage_instance_type_is_available = length(data.aws_ec2_instance_type_offering.storage.instance_type) > 0

  processed_user_data = var.user_data != "" ? templatefile(var.user_data, {
    SSH_KEYS    = join("\n", local.ssh_public_keys),
    TARGET_USER = var.target_user,
    TARGET_HOME = "/home/${var.target_user}",
    EBS_COUNT   = var.ebs_count,
    RAID_LEVEL  = var.raid_level
  }) : null

  resource_prefix = "${var.common_config.project_name}-storage"
}

resource "aws_security_group" "storage" {
  name        = "${local.resource_prefix}-sg"
  description = "Storage instance security group"
  vpc_id      = var.common_config.vpc_id

  dynamic "ingress" {
    for_each = var.allow_test_ingress ? [22] : []
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "Allow SSH from anywhere for CI/CD tests"
    }
  }

  dynamic "ingress" {
    for_each = var.allow_test_ingress ? [1] : []
    content {
      from_port   = -1
      to_port     = -1
      protocol    = "icmp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "Allow ICMP from anywhere for CI/CD tests"
    }
  }

  dynamic "ingress" {
    for_each = toset([22, 111, 2049, 42565, 47703, 50241, 52421, 60363])
    content {
      protocol    = "tcp"
      from_port   = ingress.value
      to_port     = ingress.value
      cidr_blocks = [data.aws_subnet.selected.cidr_block]
    }
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

resource "aws_instance" "this" {
  count           = var.instance_count
  ami             = var.ami
  instance_type   = var.instance_type
  user_data       = local.processed_user_data

  placement_group             = var.common_config.placement_group_name
  subnet_id                   = var.common_config.subnet_id
  key_name                    = var.common_config.key_name
  associate_public_ip_address = var.common_config.assign_public_ip

  vpc_security_group_ids = [aws_security_group.storage.id]

  root_block_device {
    volume_size = var.boot_volume_size
    volume_type = var.boot_volume_type
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
      condition = var.ebs_count >= {
        "raid-0" = 2,
        "raid-5" = 3,
        "raid-6" = 4
      }[var.raid_level]
      error_message = "The selected RAID level (${var.raid_level}) requires at least ${lookup({ "raid-0" = 2, "raid-5" = 3, "raid-6" = 4 }, var.raid_level, 0)} EBS volumes, but only ${var.ebs_count} were specified."
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

resource "aws_ebs_volume" "this" {
  count             = var.instance_count * var.ebs_count
  availability_zone = var.common_config.availability_zone
  size              = var.ebs_size
  type              = var.ebs_type
  throughput        = var.ebs_throughput
  iops              = var.ebs_iops

  tags = merge(var.common_config.tags, {
    Name    = "${local.resource_prefix}-ebs-${count.index + 1}"
    Project = var.common_config.project_name
  })
}

resource "aws_volume_attachment" "this" {
  count       = var.instance_count * var.ebs_count
  device_name = "/dev/xvd${local.device_letters[count.index % var.ebs_count]}"
  volume_id   = aws_ebs_volume.this[count.index].id
  instance_id = aws_instance.this[floor(count.index / var.ebs_count)].id
}
