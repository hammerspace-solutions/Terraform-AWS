# ansible_main.tf

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
    MGMT_IP = "${var.mgmt_ip[0]}",
    ANVIL_ID = "${var.anvil_instances[0].id}",
    STORAGE_INSTANCES = jsonencode(var.storage_instances),
    VG_NAME = "${var.volume_group_name}",
    SHARE_NAME = "${var.share_name}",
    TARGET_NODES_JSON = var.target_nodes_json,
    ADMIN_PRIVATE_KEY = var.admin_private_key
  }) : null

  resource_prefix = "${var.project_name}-ansible" 
}

# Security group for ansible instances
resource "aws_security_group" "ansible" {
  name        = "${local.resource_prefix}-sg"
  description = "Ansible instance security group"
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

# Launch EC2 Ansible instances
resource "aws_instance" "this" {
  count         = var.instance_count
  ami           = var.ami
  instance_type = var.instance_type
  subnet_id     = var.subnet_id
  key_name      = var.key_name
  user_data     = local.processed_user_data
  # placement_group        = var.placement_group_name != "" ? var.placement_group_name : null

  vpc_security_group_ids = [aws_security_group.ansible.id]

  root_block_device {
    volume_size = var.boot_volume_size
    volume_type = var.boot_volume_type
  }

  tags = merge(var.tags, {
    Name    = "${local.resource_prefix}-${count.index + 1}"
    Project = var.project_name
  })
}

