# storage_main.tf
#
# Main terraform module to deploy storage for AWS Sizing for AI Model
# creation

# Gather SSH public keys from directory and render user data if provided

locals {
  device_letters = [
    "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
    "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"
  ]

  ssh_public_keys = try(
    [
      for file in fileset(var.ssh_keys_dir, "*.pub") :
        trimspace(file("${var.ssh_keys_dir}/${file}"))
    ],
    []
  )

  processed_user_data = var.user_data != "" ? templatefile(var.user_data, {
    SSH_KEYS    = join("\n", local.ssh_public_keys),
    TARGET_USER = var.target_user,
    TARGET_HOME = "/home/${var.target_user}",
    EBS_COUNT = var.ebs_count
    RAID_LEVEL = var.raid_level
  }) : null

  resource_prefix = "${var.project_name}-storage"
}

# Security group for storage instances

resource "aws_security_group" "storage" {
  name        = "${local.resource_prefix}-sg"
  description = "Storage instance security group"
  vpc_id      = var.vpc_id

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

  tags = merge(var.tags, {
    Name    = "${local.resource_prefix}-sg"
    Project = var.project_name
  })
}

# Launch EC2 storage instances

resource "aws_instance" "this" {
  count         = var.instance_count
  placement_group = var.placement_group_name != "" ? var.placement_group_name : null
  ami           = var.ami
  instance_type = var.instance_type
  subnet_id     = var.subnet_id
  key_name      = var.key_name
  user_data     = local.processed_user_data

  vpc_security_group_ids = [aws_security_group.storage.id]

  root_block_device {
    volume_size = var.boot_volume_size
    volume_type = var.boot_volume_type
  }

  # Add this entire lifecycle block
  lifecycle {
    precondition {
      condition     = var.ebs_count >= {
        "raid-0" = 2,
        "raid-5" = 3,
        "raid-6" = 4
      }[var.raid_level]
      error_message = "The selected RAID level (${var.raid_level}) requires at least ${lookup({ "raid-0" = 2, "raid-5" = 3, "raid-6" = 4 }, var.raid_level, 0)} EBS volumes, but only ${var.ebs_count} were specified."
    }
  }

  tags = merge(var.tags, {
    Name    = "${local.resource_prefix}-${count.index + 1}"
    Project = var.project_name
  })
}

# Create extra EBS volumes for each storage

resource "aws_ebs_volume" "this" {
  count             = var.instance_count * var.ebs_count
  availability_zone = var.availability_zone
  size              = var.ebs_size
  type              = var.ebs_type
  throughput        = var.ebs_throughput
  iops              = var.ebs_iops

  tags = merge(var.tags, {
    Name    = "${local.resource_prefix}-ebs-${count.index + 1}"
    Project = var.project_name
  })
}

# Attach each EBS volume to the correct instance

resource "aws_volume_attachment" "this" {
  count       = var.instance_count * var.ebs_count
  device_name = "/dev/xvd${local.device_letters[count.index % var.ebs_count]}"
  volume_id   = aws_ebs_volume.this[count.index].id
  instance_id = aws_instance.this[floor(count.index / var.ebs_count)].id
}
