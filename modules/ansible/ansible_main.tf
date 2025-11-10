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
# modules/ansible/ansible_main.tf
#
# This file contains the main logic for the Ansible module. It creates the
# EC2 instance, security group, and processes the user data script.
# -----------------------------------------------------------------------------

data "aws_ec2_instance_type_offering" "ansible" {
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

locals {
  # Verify if the instance type is available in AWS. We will check this later with a
  # precondition

  ansible_instance_type_is_available = length(data.aws_ec2_instance_type_offering.ansible.instance_type) > 0

  # Establish resource naming prefix based upon the project name
  
  resource_prefix = "${var.common_config.project_name}-ansible"

  # Append project name to tags
  
  common_tags = merge(var.common_config.tags, {
    Project = var.common_config.project_name
  })

  # Pull keys from var or from file on disk
  
  authorized_keys_content = coalesce(
    var.authorized_keys,
    length(fileset(path.root, "ssh_keys/*.pub")) > 0
    ? join("\n", [for f in fileset(path.root, "ssh_keys/*.pub") : trimspace(file("${path.root}/${f}"))])
    : ""
  )
  authorized_keys_b64 = base64encode(local.authorized_keys_content)

  # Embed controller scripts (read from templates in this module)
  
  functions_b64 = filebase64("${path.module}/scripts/ansible_functions.sh.tmpl")
  daemon_b64    = filebase64("${path.module}/scripts/ansible_controller_daemon.sh.tmpl")

  # Embed systemd unit for the ansible controller
  
  controller_unit = <<-UNIT
  [Unit]
  Description=Ansible Controller Daemon (inventory-triggered job runner)
  Wants=network-online.target
  After=network-online.target

  [Service]
  Type=simple
  ExecStart=/usr/local/bin/ansible_controller_daemon.sh
  Restart=always
  RestartSec=5s
  User=root
  Group=root
  NoNewPrivileges=yes

  [Install]
  WantedBy=multi-user.target
  UNIT
  controller_unit_b64 = base64encode(local.controller_unit)

  # Get all the public ssh keys from the files
  
  ssh_public_keys = try(
    [
      for file in fileset(var.common_config.ssh_keys_dir, "*.pub") :
      trimspace(file("${var.common_config.ssh_keys_dir}/${file}"))
    ],
    []
  )

  # Get a minimal bootstrap template so that our services get launched
  
  daemon_script_content    = file("${path.module}/scripts/ansible_controller_daemon.sh.tmpl")
  functions_script_content = file("${path.module}/scripts/ansible_functions.sh.tmpl")

  # Create some variables needed by template file
  
  target_home = "/home/${var.target_user}"
  root_user   = "root"
  root_home   = "/${local.root_user}"

  # Process a minimal bootstrap script for user_data
  
  bootstrap_user_data = templatefile("${path.module}/scripts/bootstrap_ssh.sh.tmpl", {
    TARGET_USER = var.target_user,
    TARGET_HOME = "/home/${var.target_user}",
    SSH_KEYS    = join("\n", local.ssh_public_keys)
    PRIVATE_KEY_SECRET_ARN = var.ansible_private_key_secret_arn
    PUBLIC_KEY  = var.ansible_ssh_public_key
    REGION      = var.common_config.region
    }
  )
}

# Step 1: Create a security group for the Ansible instance(s)

resource "aws_security_group" "ansible" {
  name        = "${local.resource_prefix}-sg"
  description = "Ansible Security Group"
  vpc_id      = var.common_config.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    description = "Ingress for Ansible for SSH protocol"
    cidr_blocks = var.common_config.allowed_source_cidr_blocks
  }

  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    description = "Ingress for Ansible for ICMP protocol"
    cidr_blocks = var.common_config.allowed_source_cidr_blocks
  }

  # You should not allow access to ansible services from the internet.
  # This is for testing and should be modified to fit your needs.

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    description = "Egress for Ansible for all protocols"
    cidr_blocks = var.common_config.allowed_source_cidr_blocks
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.resource_prefix}"
    }
  )
}

# Step 2: Create EIP (if configured) for each instance in order

resource "aws_eip" "ansible" {
  count  = var.assign_public_ip ? var.instance_count : 0
  domain = "vpc"

  tags = merge(
    local.common_tags,
    {
      Name = "${local.resource_prefix}-ansible-${count.index + 1}"
    }
  )
}

# Step 3: Create those instances!

resource "aws_instance" "ansible" {
  count                  = var.instance_count
  ami                    = var.ami
  instance_type          = var.instance_type
  key_name               = var.common_config.key_name
  placement_group        = var.common_config.placement_group_name
  
  # Use the minimal bootstrap script here
  
  user_data              = local.bootstrap_user_data
  iam_instance_profile   = var.iam_profile_name

  # Define the networking directly on the instance resource

  subnet_id = var.assign_public_ip ? var.public_subnet_id : var.common_config.subnet_id
  vpc_security_group_ids = [aws_security_group.ansible.id]
  source_dest_check	 = false
  
  # Explicitly enable the EC2 Metadata Service and support both IMDSv1 and IMDSv2.
  # This allows the instance to reliably assume its IAM role.

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "optional" # Supports both IMDSv1 and IMDSv2
    http_put_response_hop_limit = 2
  }

  # Delete on shutdown
  
  root_block_device {
    delete_on_termination = true
    encrypted             = true
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.resource_prefix}-${count.index + 1}",
    }
  )
}

# Step 4: Associate the EIP with the instance's primary network interface

resource "aws_eip_association" "ansible" {
  count                = var.assign_public_ip ? var.instance_count : 0
  allocation_id        = aws_eip.ansible[count.index].id
  
  # Reference the primary ENI created by the instance itself.
  
  network_interface_id = aws_instance.ansible[count.index].primary_network_interface_id
}
