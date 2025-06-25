# modules/clients/clients_main.tf

# --- Verify that the resources for the Clients exist before continuing ---
data "aws_ec2_instance_type_offering" "clients" {
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

  client_instance_type_is_available = length(data.aws_ec2_instance_type_offering.clients.instance_type) > 0

  processed_user_data = var.user_data != "" ? templatefile(var.user_data, {
    SSH_KEYS    = join("\n", local.ssh_public_keys),
    TARGET_USER = var.target_user,
    TARGET_HOME = "/home/${var.target_user}"
  }) : null

  resource_prefix = "${var.project_name}-client"
}

# Security group for client instances
resource "aws_security_group" "client" {
  name        = "${local.resource_prefix}-sg"
  description = "Client instance security group"
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

# Launch EC2 client instances
resource "aws_instance" "this" {
  count           = var.instance_count
  ami             = var.ami
  instance_type   = var.instance_type
  subnet_id       = var.subnet_id
  key_name        = var.key_name
  user_data       = local.processed_user_data
  placement_group = var.placement_group_name != "" ? var.placement_group_name : null

  vpc_security_group_ids = [aws_security_group.client.id]

  root_block_device {
    volume_size = var.boot_volume_size
    volume_type = var.boot_volume_type
  }

  tags = merge(var.tags, {
    Name    = "${local.resource_prefix}-${count.index + 1}"
    Project = var.project_name
  })

  # --- THIS IS THE FIX ---
  # This pattern is more robust. It iterates over a map that is either empty
  # or contains the ID. If the map is empty, the block is guaranteed to
  # not be generated at all, preventing the provider crash.
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
      error_message = "ERROR: Instance type ${var.instance_type} for Clients is not available in AZ ${var.availability_zone}."
    }
  }
}

# Create extra EBS volumes for each client
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
