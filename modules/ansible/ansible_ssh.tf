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
# OUT of OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# -----------------------------------------------------------------------------
# modules/ansible/ansible_ssh.tf
#
# This file contains the logic to use public / private keys for the ansible
# controller
# -----------------------------------------------------------------------------

# Register controller's *public* key in EC2

resource "aws_key_pair" "ansible" {
  key_name   = "ansible-controller"
  public_key = var.ansible_ssh_public_key
}

# SG that allows SSH from the controller

resource "aws_security_group" "allow_ssh_from_ansible" {
  name        = "allow-ssh-from-ansible"
  description = "Allow SSH from the Ansible controller only"
  vpc_id      = var.common_config.vpc_id
}

# Prefer SG → SG

resource "aws_security_group_rule" "ssh_from_controller_sg" {
  count                    = 1
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  security_group_id        = aws_security_group.allow_ssh_from_ansible.id
  source_security_group_id = aws_security_group.ansible.id
  description              = "SSH from Ansible controller SG"
}

# Fallback to CIDR

resource "aws_security_group_rule" "ssh_from_controller_cidr" {
  count             = var.ansible_controller_cidr != null ? 1 : 0
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  security_group_id = aws_security_group.allow_ssh_from_ansible.id
  cidr_blocks       = [var.ansible_controller_cidr]
  description       = "SSH from Ansible controller CIDR"
}

resource "aws_security_group_rule" "ssh_sg_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.allow_ssh_from_ansible.id
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
}

# ---- How to attach to your target instances (or pass into modules) ----
# For each target instance/module:
# - set key_name   = aws_key_pair.ansible.key_name
# - add aws_security_group.allow_ssh_from_ansible.id to its SG list
