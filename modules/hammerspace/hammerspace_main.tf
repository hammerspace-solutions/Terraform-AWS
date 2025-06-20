# --- IAM Resources ---
resource "aws_iam_group" "admin_group" {
  count = local.create_iam_admin_group ? 1 : 0
  name  = var.iam_admin_group_id != "" ? var.iam_admin_group_id : "${var.project_name}-AnvilAdminGroup"
  path  = "/users/"
}

resource "aws_iam_role" "instance_role" {
  count = local.create_profile ? 1 : 0
  name  = "${var.project_name}-InstanceRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy" "ssh_policy" {
  count = local.create_profile ? 1 : 0
  name  = "IAMAccessSshPolicy"
  role  = aws_iam_role.instance_role[0].id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid      = "1", Effect = "Allow", Action = ["iam:ListSSHPublicKeys", "iam:GetSSHPublicKey", "iam:GetGroup"],
      Resource = compact(["arn:${data.aws_partition.current.partition}:iam::*:user/*", local.effective_iam_admin_group_arn])
    }]
  })
}

resource "aws_iam_role_policy" "ha_instance_policy" {
  count = local.create_profile ? 1 : 0
  name  = "HAInstancePolicy"
  role  = aws_iam_role.instance_role[0].id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Sid = "2", Effect = "Allow", Action = ["ec2:DescribeInstances", "ec2:DescribeInstanceAttribute", "ec2:DescribeTags"], Resource = ["*"] }]
  })
}

resource "aws_iam_role_policy" "floating_ip_policy" {
  count = local.create_profile ? 1 : 0
  name  = "FloatingIpPolicy"
  role  = aws_iam_role.instance_role[0].id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Sid = "3", Effect = "Allow", Action = ["ec2:AssignPrivateIpAddresses", "ec2:UnassignPrivateIpAddresses"], Resource = ["*"] }]
  })
}

resource "aws_iam_role_policy" "anvil_metering_policy" {
  count = local.create_profile ? 1 : 0
  name  = "AnvilMeteringPolicy"
  role  = aws_iam_role.instance_role[0].id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Sid = "4", Effect = "Allow", Action = ["aws-marketplace:MeterUsage"], Resource = ["*"] }]
  })
}

resource "aws_iam_instance_profile" "profile" {
  count = local.create_profile ? 1 : 0
  name  = "${var.project_name}-InstanceProfile"
  role  = aws_iam_role.instance_role[0].name
  tags  = local.common_tags
}

# --- Security Groups ---
resource "aws_security_group" "anvil_data_sg" {
  count       = local.should_create_any_anvils && var.anvil_security_group_id == "" ? 1 : 0
  name        = "${var.project_name}-AnvilDataSG"
  description = "Security group for Anvil metadata servers"
  vpc_id      = var.vpc_id
  tags        = local.common_tags

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.sec_ip_cidr]
  }

  ingress {
    protocol    = "icmp"
    from_port   = -1
    to_port     = -1
    cidr_blocks = [var.sec_ip_cidr]
  }
  # Anvil TCP Ports
  dynamic "ingress" {
    for_each = [22, 80, 111, 161, 443, 662, 2049, 2224, 4379, 8443, 9097, 9099, 9399, 20048, 20491, 20492, 21064, 50000, 51000, 53030]
    content {
      protocol    = "tcp"
      from_port   = ingress.value
      to_port     = ingress.value
      cidr_blocks = [var.sec_ip_cidr]
    }
  }
  ingress {
    protocol    = "tcp"
    from_port   = 4505
    to_port     = 4506
    cidr_blocks = [var.sec_ip_cidr]
  }
  ingress {
    protocol    = "tcp"
    from_port   = 7789
    to_port     = 7790
    cidr_blocks = [var.sec_ip_cidr]
  }
  ingress {
    protocol    = "tcp"
    from_port   = 9093
    to_port     = 9094
    cidr_blocks = [var.sec_ip_cidr]
  }
  ingress {
    protocol    = "tcp"
    from_port   = 9298
    to_port     = 9299
    cidr_blocks = [var.sec_ip_cidr]
  }
  ingress {
    protocol    = "tcp"
    from_port   = 41001
    to_port     = 41256
    cidr_blocks = [var.sec_ip_cidr]
  }
  ingress {
    protocol    = "tcp"
    from_port   = 52000
    to_port     = 52008
    cidr_blocks = [var.sec_ip_cidr]
  }
  ingress {
    protocol    = "tcp"
    from_port   = 53000
    to_port     = 53008
    cidr_blocks = [var.sec_ip_cidr]
  }
  # Anvil UDP Ports
  dynamic "ingress" {
    for_each = [111, 123, 161, 662, 4379, 5405, 20048]
    content {
      protocol    = "udp"
      from_port   = ingress.value
      to_port     = ingress.value
      cidr_blocks = [var.sec_ip_cidr]
    }
  }
}

resource "aws_security_group" "dsx_sg" {
  count       = var.dsx_count > 0 && var.dsx_security_group_id == "" ? 1 : 0
  name        = "${var.project_name}-DsxSG"
  description = "Security group for DSX data services nodes"
  vpc_id      = var.vpc_id
  tags        = local.common_tags

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.sec_ip_cidr]
  }

  ingress {
    protocol    = "icmp"
    from_port   = -1
    to_port     = -1
    cidr_blocks = [var.sec_ip_cidr]
  }
  # DSX TCP Ports
  dynamic "ingress" {
    for_each = [22, 111, 139, 161, 445, 662, 2049, 3049, 4379, 9093, 9292, 20048, 20491, 20492, 30048, 30049, 50000, 51000, 53030]
    content {
      protocol    = "tcp"
      from_port   = ingress.value
      to_port     = ingress.value
      cidr_blocks = [var.sec_ip_cidr]
    }
  }
  ingress {
    protocol    = "tcp"
    from_port   = 4505
    to_port     = 4506
    cidr_blocks = [var.sec_ip_cidr]
  }
  ingress {
    protocol    = "tcp"
    from_port   = 9000
    to_port     = 9009
    cidr_blocks = [var.sec_ip_cidr]
  }
  ingress {
    protocol    = "tcp"
    from_port   = 9095
    to_port     = 9096
    cidr_blocks = [var.sec_ip_cidr]
  }
  ingress {
    protocol    = "tcp"
    from_port   = 9098
    to_port     = 9099
    cidr_blocks = [var.sec_ip_cidr]
  }
  ingress {
    protocol    = "tcp"
    from_port   = 41001
    to_port     = 41256
    cidr_blocks = [var.sec_ip_cidr]
  }
  ingress {
    protocol    = "tcp"
    from_port   = 52000
    to_port     = 52008
    cidr_blocks = [var.sec_ip_cidr]
  }
  ingress {
    protocol    = "tcp"
    from_port   = 53000
    to_port     = 53008
    cidr_blocks = [var.sec_ip_cidr]
  }
  # DSX UDP Ports
  dynamic "ingress" {
    for_each = [111, 161, 662, 20048, 30048, 30049]
    content {
      protocol    = "udp"
      from_port   = ingress.value
      to_port     = ingress.value
      cidr_blocks = [var.sec_ip_cidr]
    }
  }
}

# --- Anvil Standalone Resources ---
resource "aws_network_interface" "anvil_sa_ni" {
  count           = local.create_standalone_anvil ? 1 : 0
  subnet_id       = var.subnet_id
  security_groups = local.effective_anvil_sg_id != null ? [local.effective_anvil_sg_id] : []
  tags            = merge(local.common_tags, { Name = "${var.project_name}-Anvil-NI" })
  depends_on      = [aws_security_group.anvil_data_sg]
}
resource "aws_instance" "anvil" {
  count                  = local.create_standalone_anvil ? 1 : 0
  ami                    = var.ami
  instance_type          = local.anvil_instance_type_actual
  availability_zone      = var.availability_zone
  key_name               = local.provides_key_name ? var.key_name : null
  iam_instance_profile   = local.effective_instance_profile_ref
  user_data_base64       = base64encode(jsonencode(local.anvil_sa_config_map))
  placement_group        = var.placement_group_name != "" ? var.placement_group_name : null

  lifecycle {
    precondition {
      condition     = var.sa_anvil_destruction == true
      error_message = "The standalone Anvil is protected. To destroy it, set 'hammerspace_allow_standalone_anvil_destruction = true'."
    }
  }

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.anvil_sa_ni[0].id
  }
  root_block_device {
    volume_type = "gp3"
    volume_size = 200
  }
  tags = merge(local.common_tags, { Name = "${var.project_name}-Anvil" })
  depends_on = [aws_iam_instance_profile.profile]
}
resource "aws_ebs_volume" "anvil_meta_vol" {
  count               = local.create_standalone_anvil ? 1 : 0
  availability_zone   = var.availability_zone
  size                = var.anvil_meta_disk_size
  type                = var.anvil_meta_disk_type
  iops                = contains(["io1", "io2", "gp3"], var.anvil_meta_disk_type) ? var.anvil_meta_disk_iops : null
  throughput          = var.anvil_meta_disk_type == "gp3" ? var.anvil_meta_disk_throughput : null
  tags                = merge(local.common_tags, { Name = "${var.project_name}-Anvil-MetaVol" })
}
resource "aws_volume_attachment" "anvil_meta_vol_attach" {
  count       = local.create_standalone_anvil ? 1 : 0
  device_name = "/dev/sdb"
  instance_id = aws_instance.anvil[0].id
  volume_id   = aws_ebs_volume.anvil_meta_vol[0].id
}

# --- Anvil HA Resources ---
resource "aws_network_interface" "anvil1_ha_ni" {
  count           = local.create_ha_anvils ? 1 : 0
  subnet_id       = var.subnet_id
  security_groups = local.effective_anvil_sg_id != null ? [local.effective_anvil_sg_id] : []
  tags            = merge(local.common_tags, { Name = "${var.project_name}-Anvil1-NI" })
  depends_on      = [aws_security_group.anvil_data_sg]
}
resource "aws_instance" "anvil1" {
  count                  = local.create_ha_anvils ? 1 : 0
  ami                    = var.ami
  instance_type          = local.anvil_instance_type_actual
  availability_zone      = var.availability_zone
  key_name               = local.provides_key_name ? var.key_name : null
  iam_instance_profile   = local.effective_instance_profile_ref
  user_data_base64       = base64encode(jsonencode(merge(local.anvil_ha_config_map, { "node_index" = "0" })))
  placement_group        = var.placement_group_name != "" ? var.placement_group_name : null

  lifecycle {
    precondition {
      condition     = length(aws_instance.anvil) == 0
      error_message = "Changing from a 1-node standalone Anvil to a 2-node HA Anvil is a destructive action and is not allowed. Please destroy the old environment first and then create the new HA environment."
    }
  }

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.anvil1_ha_ni[0].id
  }
  root_block_device {
    volume_type = "gp3"
    volume_size = 200
  }
  tags = merge(local.common_tags, { Name = "${var.project_name}-Anvil1", Index = "0" })
  depends_on = [aws_iam_instance_profile.profile]
}
resource "aws_ebs_volume" "anvil1_meta_vol" {
  count               = local.create_ha_anvils ? 1 : 0
  availability_zone   = var.availability_zone
  size                = var.anvil_meta_disk_size
  type                = var.anvil_meta_disk_type
  iops                = contains(["io1", "io2", "gp3"], var.anvil_meta_disk_type) ? var.anvil_meta_disk_iops : null
  throughput          = var.anvil_meta_disk_type == "gp3" ? var.anvil_meta_disk_throughput : null
  tags                = merge(local.common_tags, { Name = "${var.project_name}-Anvil1-MetaVol" })
}
resource "aws_volume_attachment" "anvil1_meta_vol_attach" {
  count       = local.create_ha_anvils ? 1 : 0
  device_name = "/dev/sdb"
  instance_id = aws_instance.anvil1[0].id
  volume_id   = aws_ebs_volume.anvil1_meta_vol[0].id
}

resource "aws_network_interface" "anvil2_ha_ni" {
  count             = local.create_ha_anvils ? 1 : 0
  subnet_id         = var.subnet_id
  security_groups   = local.effective_anvil_sg_id != null ? [local.effective_anvil_sg_id] : []
  private_ips_count = 1
  tags              = merge(local.common_tags, { Name = "${var.project_name}-Anvil2-NI" })
  depends_on        = [aws_security_group.anvil_data_sg]
}
resource "aws_instance" "anvil2" {
  count                  = local.create_ha_anvils ? 1 : 0
  ami                    = var.ami
  instance_type          = local.anvil_instance_type_actual
  availability_zone      = var.availability_zone
  key_name               = local.provides_key_name ? var.key_name : null
  iam_instance_profile   = local.effective_instance_profile_ref
  user_data_base64       = base64encode(jsonencode(merge(local.anvil_ha_config_map, { "node_index" = "1" })))
  placement_group        = var.placement_group_name != "" ? var.placement_group_name : null

  lifecycle {
    precondition {
      condition     = length(aws_instance.anvil) == 0
      error_message = "Changing from a 1-node standalone Anvil to a 2-node HA Anvil is a destructive action and is not allowed. Please destroy the old environment first and then create the new HA environment."
    }
  }

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.anvil2_ha_ni[0].id
  }
  root_block_device {
    volume_type = "gp3"
    volume_size = 200
  }
  tags = merge(local.common_tags, { Name = "${var.project_name}-Anvil2", Index = "1" })
  depends_on = [aws_instance.anvil1, aws_iam_instance_profile.profile]
}
resource "aws_ebs_volume" "anvil2_meta_vol" {
  count               = local.create_ha_anvils ? 1 : 0
  availability_zone   = length(aws_instance.anvil2) > 0 ? aws_instance.anvil2[0].availability_zone : var.availability_zone
  size                = var.anvil_meta_disk_size
  type                = var.anvil_meta_disk_type
  iops                = contains(["io1", "io2", "gp3"], var.anvil_meta_disk_type) ? var.anvil_meta_disk_iops : null
  throughput          = var.anvil_meta_disk_type == "gp3" ? var.anvil_meta_disk_throughput : null
  tags                = merge(local.common_tags, { Name = "${var.project_name}-Anvil2-MetaVol" })
}
resource "aws_volume_attachment" "anvil2_meta_vol_attach" {
  count       = local.create_ha_anvils ? 1 : 0
  device_name = "/dev/sdb"
  instance_id = aws_instance.anvil2[0].id
  volume_id   = aws_ebs_volume.anvil2_meta_vol[0].id
}

# --- DSX Data Services Node Resources ---
resource "aws_network_interface" "dsx_ni" {
  count               = var.dsx_count
  subnet_id           = var.subnet_id
  security_groups     = local.effective_dsx_sg_id != null ? [local.effective_dsx_sg_id] : []
  source_dest_check   = false
  tags                = merge(local.common_tags, { Name = "${var.project_name}-DSX${count.index + 1}-NI" })
  depends_on          = [aws_security_group.dsx_sg]
}
resource "aws_instance" "dsx" {
  count                  = var.dsx_count
  ami                    = var.ami
  instance_type          = local.dsx_instance_type_actual
  availability_zone      = var.availability_zone
  key_name               = local.provides_key_name ? var.key_name : null
  iam_instance_profile   = local.effective_instance_profile_ref
  placement_group        = var.placement_group_name != "" ? var.placement_group_name : null
  user_data_base64 = base64encode(jsonencode({
    cluster = {
      password_auth = false,
      password      = local.effective_anvil_id_for_dsx_password,
      metadata = {
        ips = (local.effective_anvil_ip_for_dsx_metadata != null ? ["${local.effective_anvil_ip_for_dsx_metadata}/20"] : [])
      }
    }
    nodes = merge(
      {
        "0" = {
          hostname    = "${var.project_name}DSX${count.index + 1}"
          features    = ["storage", "portal"]
          add_volumes = local.dsx_add_volumes_bool
          networks = {
            eth0 = {
              roles = ["data", "mgmt"]
            }
          }
        }
      },
      local.anvil_nodes_map_for_dsx
    )
    aws = local.aws_config_map
  }))
  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.dsx_ni[count.index].id
  }
  root_block_device {
    volume_type = "gp3"
    volume_size = 200
  }
  tags = merge(local.common_tags, { Name = "${var.project_name}-DSX${count.index + 1}" })
  depends_on = [aws_iam_instance_profile.profile]
}

resource "aws_ebs_volume" "dsx_data_vols" {
  count = var.dsx_count * var.dsx_ebs_count

  availability_zone = var.availability_zone
  size              = var.dsx_ebs_size
  type              = var.dsx_ebs_type
  iops              = contains(["io1", "io2", "gp3"], var.dsx_ebs_type) ? var.dsx_ebs_iops : null
  throughput        = var.dsx_ebs_type == "gp3" ? var.dsx_ebs_throughput : null
  tags = merge(local.common_tags, {
    Name             = "${var.project_name}-DSX${floor(count.index / var.dsx_ebs_count) + 1}-DataVol${(count.index % var.dsx_ebs_count) + 1}"
    DSXInstanceIndex = floor(count.index / var.dsx_ebs_count)
    VolumeIndex      = count.index % var.dsx_ebs_count
  })
}

resource "aws_volume_attachment" "dsx_data_vols_attach" {
  count = var.dsx_count * var.dsx_ebs_count

  device_name = "/dev/xvd${local.device_letters[count.index % var.dsx_ebs_count]}"
  volume_id   = aws_ebs_volume.dsx_data_vols[count.index].id
  instance_id = aws_instance.dsx[floor(count.index / var.dsx_ebs_count)].id
}
