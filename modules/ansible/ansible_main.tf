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

  # Get all the public ssh keys from the files
  
  ssh_public_keys = try(
    [
      for file in fileset(var.common_config.ssh_keys_dir, "*.pub") :
        trimspace(file("${var.common_config.ssh_keys_dir}/${file}"))
    ],
    []
  )

  # Verify if the instance type is available in AWS. We will check this later with a
  # precondition
  
  ansible_instance_type_is_available = length(data.aws_ec2_instance_type_offering.ansible.instance_type) > 0

  # This reads the entire content of the "ansible_controller_daemon.sh" file
  # into a single string and stores it in the 'daemon_script_content' variable.

  daemon_script_content = file("${path.module}/scripts/ansible_controller_daemon.sh.tmpl")

  # This does the same for the "ansible_functions.sh" file.

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
  
  # Process the template file and substitute arguments
  
  processed_ansible_script_content = templatefile(
    "${path.module}/scripts/ansible_config.sh.tmpl", {
      daemon_script	     = local.daemon_script_content,
      functions_script	     = local.functions_script_content
    }
  )

  resource_prefix = "${var.common_config.project_name}-ansible"

  common_tags = merge(var.common_config.tags, {
    Project = var.common_config.project_name
  })
}

# Security group for ansible instances

resource "aws_security_group" "ansible" {
  name        = "${local.resource_prefix}-sg"
  description = "Ansible instance security group"
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

  tags = merge(local.common_tags, {
    Name    = "${local.resource_prefix}-sg"
  })
}

# One EIP per instance, but only when we want a public IP

resource "aws_eip" "ansible" {
  count	 	      = var.assign_public_ip ? var.instance_count : 0
  domain	      = "vpc"
  tags		      = merge(local.common_tags, { Name = "${var.common_config.project_name}-Ansible-EIP" })
}

# Associate EIP to the Instance (not to an ENI)

resource "aws_eip_association" "ansible" {
  count	 	           = var.assign_public_ip ? var.instance_count : 0
  allocation_id		   = aws_eip.ansible[count.index].id
  instance_id		   = aws_instance.ansible[count.index].id
}

# Launch EC2 Ansible instances

resource "aws_instance" "ansible" {
  count         = var.instance_count
  ami           = var.ami
  instance_type = var.instance_type
  key_name        = var.common_config.key_name
  placement_group = var.common_config.placement_group_name

  # Use the minimal bootstrap script here

  user_data     = local.bootstrap_user_data
  
  # Primary interface via native args

  subnet_id     = var.assign_public_ip ? var.public_subnet_id : var.common_config.subnet_id
  vpc_security_group_ids = [aws_security_group.ansible.id]
  iam_instance_profile = var.iam_profile_name
  
  # Never associate a public IP; we will attach an EIP when requested

  associate_public_ip_address = false

  # Put tags on the volumes

  volume_tags = merge(local.common_tags, {
    Name   = "${local.resource_prefix}-vol"
  })

  # Create the boot disk
  
  root_block_device {
    volume_size               = var.boot_volume_size
    volume_type 	      = var.boot_volume_type
    delete_on_termination     = true
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
      condition     = !(var.assign_public_ip && var.public_subnet_id == null)
      error_message = "If 'assign_public_ip' is true for Ansible, 'public_subnet_id' must be provided."
    }
    precondition {
      condition     = local.ansible_instance_type_is_available
      error_message = "ERROR: Instance type ${var.instance_type} for the Ansible is not available in AZ ${var.common_config.availability_zone}."
    }
  }
  
  tags = merge(local.common_tags, {
    Name    = "${local.resource_prefix}-${count.index + 1}"
  })
}

# Use a null_resource to conditionally run provisioners. This resource
# does nothing by itself, but allows us to use `count` to control whether
# the provisioners inside it are executed.

resource "null_resource" "key_provisioner" {
  # Only create this resource (and run its provisioners) if a key path is provided.
  count = var.admin_private_key_path != "" ? var.instance_count : 0

  # Make sure the EIP is associated before we try to connect publicly
  # Safe to list even when count=0

  depends_on = [
    aws_instance.ansible,
    aws_eip_association.ansible
  ]

  # This trigger ensures the provisioner runs after the instance is created.

  triggers = {
    instance_id = aws_instance.ansible[count.index].id
    # Prefer EIP when requested; fall back to instance pub/private to avoid empty host
    host = (
      var.assign_public_ip
      ? coalesce(
          try(aws_eip.ansible[count.index].public_ip, ""),
          try(aws_instance.ansible[count.index].public_ip, ""),
          aws_instance.ansible[count.index].private_ip
        )
      : aws_instance.ansible[count.index].private_ip
    )
  }

  # Single connection for everything... We use root as the user as we
  # have to handle files for root and other users
  
  connection {
    type        = "ssh"
    user        = local.root_user
    # The key used for the initial connection is the main one for the instance.
    private_key = file(var.admin_private_key_path)
    host = (
      var.assign_public_ip
      ? coalesce(
          try(aws_eip.ansible[count.index].public_ip, ""),
          try(aws_instance.ansible[count.index].public_ip, ""),
          aws_instance.ansible[count.index].private_ip
        )
      : aws_instance.ansible[count.index].private_ip
    )
  }

  # Provisioner copies the key file.

  provisioner "file" {
    source      = var.admin_private_key_path
    destination = "/home/${var.target_user}/.ssh/id_rsa"

  }

  # Provisioner sets the correct permissions on the uploaded key.

  provisioner "remote-exec" {
    inline = [
      "sudo chmod 600 /home/${var.target_user}/.ssh/id_rsa",
      "sudo chown ${var.target_user}:${var.target_user} /home/${var.target_user}/.ssh/id_rsa"
    ]
  }

  # Third provisioner copies the public key file.

  provisioner "file" {
    source      = var.admin_public_key_path
    destination = "/home/${var.target_user}/.ssh/id_rsa.pub"
  }

  # Provisioner sets the correct permissions on the uploaded key.

  provisioner "remote-exec" {
    inline = [
      "sudo chmod 600 /home/${var.target_user}/.ssh/id_rsa.pub",
      "sudo chown ${var.target_user}:${var.target_user} /home/${var.target_user}/.ssh/id_rsa.pub"
    ]
  }

  # Provisioner to upload the main configuration script

  provisioner "file" {
    content       = local.processed_ansible_script_content
    destination	  = "/tmp/run_ansible_setup.sh"
  }

  # Provisioner to execute the main configuration script

  provisioner "remote-exec" {
    inline = [
      "sudo chmod +x /tmp/run_ansible_setup.sh",
      "sudo bash -c /tmp/run_ansible_setup.sh"
    ]
  }

  # Provisioner copies the key file to root.

  provisioner "file" {
    source      = var.admin_private_key_path
    destination = "${local.root_home}/.ssh/id_rsa"
  }

  # Provisioner sets the correct permissions on the uploaded key on root.

  provisioner "remote-exec" {
    inline = [
      "sudo chmod 600 ${local.root_home}/.ssh/id_rsa",
      "sudo chown ${local.root_user}:${local.root_user} ${local.root_home}/.ssh/id_rsa"
    ]
  }

  # Provisioner copies the public key file to root.

  provisioner "file" {
    source      = var.admin_public_key_path
    destination = "${local.root_home}/.ssh/id_rsa.pub"
  }

  # Provisioner sets the correct permissions on the uploaded key in root.

  provisioner "remote-exec" {
    inline = [
      "sudo chmod 600 ${local.root_home}/.ssh/id_rsa.pub",
      "sudo chown ${local.root_user}:${local.root_user} ${local.root_home}/.ssh/id_rsa.pub"
    ]
  }
}
