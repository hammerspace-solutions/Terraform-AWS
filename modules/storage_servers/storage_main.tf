# modules/storage_servers/storage_main.tf

data "aws_ec2_instance_type_offering" "storage" {
  filter {
    name   = "instance-type"
    values = [var.instance_type]
  }
  filter {
    name   = "location"
    values = [var.availability_zone]
  }
  location_type = "availability-zone"
}

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

  storage_instance_type_is_available = length(data.aws_ec2_instance_type_offering.storage.instance_type) > 0

  processed_user_data = var.user_data != "" ? templatefile(var.user_data, {
    SSH_KEYS    = join("\n", local.ssh_public_keys),
    TARGET_USER = var.target_user,
    TARGET_HOME = "/home/${var.target_user}",
    EBS_COUNT   = var.ebs_count,
    RAID_LEVEL  = var.raid_level
  }) : null

  resource_prefix = "${var.project_name}-storage"
}

resource "aws_security_group" "storage" {
  name        = "${local.resource_prefix}-sg"
  description = "Storage instance security group"
  vpc_id      = var.vpc_id

  # --- THIS IS THE FIX ---
  # These dynamic blocks will only generate ingress rules if the
  # new `allow_test_ingress` variable is set to true.

  # Rule for SSH (TCP port 22)

  dynamic "ingress" {
    for_each = var.allow_test_ingress ? [22] : []
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  # Rule for ICMP (Ping)

  dynamic "ingress" {
    for_each = var.allow_test_ingress ? [1] : []
    content {
      from_port   = -1 # -1 means "all" for ICMP type
      to_port     = -1 # -1 means "all" for ICMP code
      protocol    = "icmp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  # Rule for when we are NOT doing testing

  dynamic "ingress" {
    for_each = !var.allow_test_ingress ? [1] : []
    content {
      from_port	  = 0
      to_port	  = 0
      protocol	  = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
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

resource "aws_instance" "this" {
  count           = var.instance_count
  placement_group = var.placement_group_name != "" ? var.placement_group_name : null
  ami             = var.ami
  instance_type   = var.instance_type
  subnet_id       = var.subnet_id
  key_name        = var.key_name
  user_data       = local.processed_user_data

  associate_public_ip_address = var.assign_public_ip
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
      error_message = "ERROR: Instance type ${var.instance_type} for Storage is not available in AZ ${var.availability_zone}."
    }
  }

  tags = merge(var.tags, {
    Name    = "${local.resource_prefix}-${count.index + 1}"
    Project = var.project_name
  })
}

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

resource "aws_volume_attachment" "this" {
  count       = var.instance_count * var.ebs_count
  device_name = "/dev/xvd${local.device_letters[count.index % var.ebs_count]}"
  volume_id   = aws_ebs_volume.this[count.index].id
  instance_id = aws_instance.this[floor(count.index / var.ebs_count)].id
}
