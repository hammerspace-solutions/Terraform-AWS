# ecg_main.tf
#
# Main terraform module to deploy ecg for AWS Sizing for AI Model
# creation

# Gather SSH public keys from directory and render user data if provided

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
    SSH_KEYS    = join("\n", local.ssh_public_keys)
   }) : null

  resource_prefix = "${var.common_config.project_name}-ecgroup"
}

# Security group for ecgroup instances

resource "aws_security_group" "this" {
  name        = "${local.resource_prefix}-sg"
  description = "ECGroup instance security group"
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

# Launch EC2 ecg instances

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
    volume_size = var.boot_volume_size
    volume_type = var.boot_volume_type
  }

  # Add this entire lifecycle block

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

# Create extra EBS metadata volume for each node

resource "aws_ebs_volume" "metadata" {
  count             = var.node_count
  availability_zone = var.common_config.availability_zone
  size              = var.metadata_ebs_size
  type              = var.metadata_ebs_type
  throughput        = var.metadata_ebs_throughput
  iops              = var.metadata_ebs_iops

  tags = merge(var.common_config.tags, {
    Name    = "${local.resource_prefix}-metadata-ebs"
    Project = var.common_config.project_name
  })
}

# Create extra EBS storage volumes for each node

resource "aws_ebs_volume" "storage" {
  count             = var.node_count * var.storage_ebs_count
  availability_zone = var.common_config.availability_zone
  size              = var.storage_ebs_size
  type              = var.storage_ebs_type
  throughput        = var.storage_ebs_throughput
  iops              = var.storage_ebs_iops

  tags = merge(var.common_config.tags, {
    Name    = "${local.resource_prefix}-storage-ebs-${count.index + 1}"
    Project = var.common_config.project_name
  })
}

# Attach each EBS metadata volume to the correct instance

resource "aws_volume_attachment" "metadata" {
  count       = var.node_count
  device_name = "/dev/xvdz"
  volume_id   = aws_ebs_volume.metadata[count.index].id
  instance_id = aws_instance.nodes[count.index].id
}

# Attach each EBS storage volumes to the correct instance

resource "aws_volume_attachment" "storage" {
  count       = var.node_count * var.storage_ebs_count
  device_name = "/dev/xvd${local.device_letters[count.index % var.storage_ebs_count]}"
  volume_id   = aws_ebs_volume.storage[count.index].id
  instance_id = aws_instance.nodes[floor(count.index / var.storage_ebs_count)].id
}
