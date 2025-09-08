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
  daemon_b64 = filebase64("${path.module}/scripts/ansible_controller_daemon.sh.tmpl")

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
  
  daemon_script_content = file("${path.module}/scripts/ansible_controller_daemon.sh.tmpl")

  functions_script_content = file("${path.module}/scripts/ansible_functions.sh.tmpl")

  # Create some variables needed by template file

  target_home		   = "/home/${var.target_user}"
  root_user 		   = "root"
  root_home 		   = "/${local.root_user}"

  # Process a minimal bootstrap script for user_data

  bootstrap_user_data = templatefile("${path.module}/scripts/bootstrap_ssh.sh.tmpl", {
    TARGET_USER              = var.target_user,
    TARGET_HOME		     = "/home/${var.target_user}",
    SSH_KEYS		     = join("\n", local.ssh_public_keys)
    }
  )
}

# Step 1: Create a security group for the Ansible instance(s)

resource "aws_security_group" "ansible" {
  name          = "${local.resource_prefix}-sg"
  description   = "Ansible Security Group"
  vpc_id        = var.common_config.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port	= 22
    protocol    = "tcp"
    cidr_blocks = var.common_config.allowed_source_cidr_blocks
  }

  ingress {
    description	= "ICMP (ping) - temp for testing"
    from_port	= -1
    to_port	= -1
    protocol	= "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # You should not allow access to ansible services from the internet.
  # This is for testing and should be modified to fit your needs.

  egress {
    description = "ALL"
    from_port   = 0
    to_port	= 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
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
  count	             = var.assign_public_ip ? var.instance_count : 0
  domain             = "vpc"

  tags = merge(
    local.common_tags,
    { 
        Name = "${local.resource_prefix}-ansible-${count.index+1}"
    }
  )
}

# Step 3: Create network interfaces for each instance

resource "aws_network_interface" "ansible_primary" {
  count	        = var.instance_count
  subnet_id     = var.assign_public_ip ? var.public_subnet_id : var.common_config.subnet_id
  security_groups = [ aws_security_group.ansible.id ]

  source_dest_check	   = false

  tags = merge(
    local.common_tags,
    { 
        Name = "${local.resource_prefix}-${count.index+1}"
    }
  )
}

# Step 4: Attach to any EIP # so that it can be used for the primary network interface

resource "aws_eip_association" "ansible" {
  count	       = var.assign_public_ip ? var.instance_count : 0
  allocation_id	= aws_eip.ansible[count.index].id
  network_interface_id = aws_network_interface.ansible_primary[count.index].id
}

# Step 4: Create those instances!

resource "aws_instance" "ansible" {
  count         = var.instance_count
  ami           = var.ami
  instance_type = var.instance_type
  key_name        = var.common_config.key_name
  placement_group = var.common_config.placement_group_name

  # Use the minimal bootstrap script here

  user_data     = local.bootstrap_user_data
  
  # Using the ENI as eth0

  primary_network_interface {
    network_interface_id = aws_network_interface.ansible_primary[count.index].id
  }
  
  # Primary interface via native args

  iam_instance_profile	   = var.iam_profile_name

  # Delete on shutdown

  root_block_device {
    delete_on_termination = true
    encrypted		   = true
  }

  tags = merge(
    local.common_tags,
    { 
      Name = "${local.resource_prefix}-${count.index+1}",
    }
  )
}

# Wait for SSM agent to come online before creating the association

resource "time_sleep" "wait_for_ssm_agent" {
  count           = var.use_ssm_bootstrap ? 1 : 0
  create_duration = var.ssm_bootstrap_delay
  depends_on	  = [aws_instance.ansible]
}

# Step 5: Create SSM document (idempotent, safe to re-run)

resource "aws_ssm_document" "ansible_bootstrap" {
  count         = var.use_ssm_bootstrap ? 1 : 0
  name          = "${local.resource_prefix}-ansible-bootstrap"
  document_type = "Command"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Bootstrap the Ansible host: install controller + authorized_keys (via SSM)"
    parameters = {
      TargetUser   = { type = "String", description = "Linux user to receive authorized_keys (in addition to root)" }
      AuthorizedB64 = { type = "String", description = "Base64 authorized_keys content" }
      FunctionsB64  = { type = "String", description = "Base64 functions script" }
      DaemonB64     = { type = "String", description = "Base64 daemon script" }
      UnitB64       = { type = "String", description = "Base64 systemd unit" }
    }
    mainSteps = [{
      name   = "BootstrapAnsibleHost"
      action = "aws:runShellScript"
      inputs = {
        runCommand = [
	  "# --- idempotency guard: skip install if files already present ---",
          "if [ -f /usr/local/bin/ansible_controller_daemon.sh ] && systemctl list-unit-files | grep -q '^ansible-controller.service'; then",
          "  SKIP_INSTALL=1",
          "else",
          "  SKIP_INSTALL=0",
          "fi",

          "# --- helper: append + dedupe authorized_keys ---",
          "append_auth_keys() { target=\"$1\"; tmp=\"/tmp/authorized_keys.$$\"; umask 077; echo {{ AuthorizedB64 }} | base64 -d > \"$tmp\" || true; sed -i 's/\\r$//' \"$tmp\" 2>/dev/null || true; touch \"$target\" && chmod 600 \"$target\"; while IFS= read -r line; do [ -z \"$line\" ] && continue; case \"$line\" in \\#*) continue ;; esac; grep -qxF \"$line\" \"$target\" || echo \"$line\" >> \"$target\"; done < \"$tmp\"; rm -f \"$tmp\"; }",

          "# --- always: root keys ---",
          "install -d -m 0700 /root/.ssh",
          "append_auth_keys /root/.ssh/authorized_keys",

          "# --- also: target user keys unless root ---",
          "U='{{ TargetUser }}'",
          "if [ \"$U\" != \"root\" ]; then",
          "  HOME_DIR=$(getent passwd \"$U\" | cut -d: -f6 || echo \"/home/$U\")",
          "  install -d -m 0700 \"$HOME_DIR/.ssh\"",
          "  append_auth_keys \"$HOME_DIR/.ssh/authorized_keys\"",
          "  chown -R \"$U\":\"$U\" \"$HOME_DIR/.ssh\"",
          "fi",

          "# --- install controller files only if not present ---",
          "if [ \"$SKIP_INSTALL\" -eq 0 ]; then",
          "  echo {{ FunctionsB64 }} | base64 -d > /usr/local/lib/ansible_functions.sh",
          "  chmod 0644 /usr/local/lib/ansible_functions.sh",

          "  echo {{ DaemonB64 }} | base64 -d > /usr/local/bin/ansible_controller_daemon.sh",
          "  chmod 0755 /usr/local/bin/ansible_controller_daemon.sh",

          "  echo {{ UnitB64 }} | base64 -d > /etc/systemd/system/ansible-controller.service",
	  "fi",

          "# --- systemd ---",
          "systemctl daemon-reload",
          "systemctl enable --now ansible-controller.service"
        ]
      }
    }]
  })
}

# Step 6: Associate the ssm document with all instances (retry via schedule; no CLI)

resource "aws_ssm_association" "ansible_bootstrap" {
  count = (var.use_ssm_bootstrap ? var.instance_count : 0)

  name = aws_ssm_document.ansible_bootstrap[0].name

  targets {
    key    = "InstanceIds"
    values = [aws_instance.ansible[count.index].id]
  }

  # Retry via State Manager schedule (runs now and per schedule)
  schedule_expression = (
    var.ssm_association_schedule != null && var.ssm_association_schedule != ""
    ? var.ssm_association_schedule
    : null
  )

  parameters = {
    TargetUser    = var.target_user
    AuthorizedB64 = local.authorized_keys_b64
    FunctionsB64  = local.functions_b64
    DaemonB64     = local.daemon_b64
    UnitB64       = local.controller_unit_b64
  }

  depends_on = [aws_instance.ansible,
  	        time_sleep.wait_for_ssm_agent]
}
