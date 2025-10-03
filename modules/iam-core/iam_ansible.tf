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
# modules/iam-core/iam_ansible.tf
#
# This file contains IAM resources specific to the Ansible controller, including
# SSM permissions and access to the Ansible private key in Secrets Manager.
# -----------------------------------------------------------------------------

locals {
  ansible_resource_prefix = "${var.common_config.project_name}-ansible"
}

resource "aws_iam_role" "ansible_controller" {
  count = var.ansible_private_key_secret_arn != null ? 1 : 0

  name = "${local.ansible_resource_prefix}-role"
  path = var.role_path
  tags = merge(local.common_tags, {
    Name = "${local.ansible_resource_prefix}-role"
  })

  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

# Inline policy for SSM core permissions (consolidated here since SSM is only for Ansible)
data "aws_iam_policy_document" "ansible_ssm_core" {
  count = var.ansible_private_key_secret_arn != null ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "ssm:DescribeAssociation",
      "ssm:GetDeployablePatchSnapshotForInstance",
      "ssm:GetDocument",
      "ssm:DescribeDocument",
      "ssm:GetManifest",
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:ListAssociations",
      "ssm:ListInstanceAssociations",
      "ssm:PutInventory",
      "ssm:PutComplianceItems",
      "ssm:PutConfigurePackageResult",
      "ssm:UpdateAssociationStatus",
      "ssm:UpdateInstanceAssociationStatus",
      "ssm:UpdateInstanceInformation",
      "ssm:SendCommand",
      "ssm:GetCommandInvocation",
      "ssm:ListCommands",
      "ssm:ListCommandInvocations",
      "ssm:StartSession",
      "ssm:TerminateSession",
      "ssm:ResumeSession"
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel"
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ec2messages:AcknowledgeMessage",
      "ec2messages:DeleteMessage",
      "ec2messages:FailMessage",
      "ec2messages:GetEndpoint",
      "ec2messages:GetMessages",
      "ec2messages:SendReply"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ansible_ssm_core" {
  count = var.ansible_private_key_secret_arn != null ? 1 : 0

  name   = "${local.ansible_resource_prefix}-SSMCustomPolicy"
  role   = aws_iam_role.ansible_controller[0].id
  policy = data.aws_iam_policy_document.ansible_ssm_core[0].json
}

# Policy for Secrets Manager access (specific to Ansible private key)
data "aws_iam_policy_document" "ansible_secrets" {
  count = var.ansible_private_key_secret_arn != null ? 1 : 0

  statement {
    sid     = "SecretsRead"
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    resources = [var.ansible_private_key_secret_arn]
  }
}

resource "aws_iam_role_policy" "ansible_secrets" {
  count = var.ansible_private_key_secret_arn != null ? 1 : 0

  name   = "${local.ansible_resource_prefix}-SecretsPolicy"
  role   = aws_iam_role.ansible_controller[0].id
  policy = data.aws_iam_policy_document.ansible_secrets[0].json
}

# Attach extra managed policies if provided
resource "aws_iam_role_policy_attachment" "ansible_extra" {
  for_each = var.ansible_private_key_secret_arn != null ? toset(var.extra_managed_policy_arns) : toset([])

  role       = aws_iam_role.ansible_controller[0].name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "ansible_controller" {
  count = var.ansible_private_key_secret_arn != null ? 1 : 0

  name = "${local.ansible_resource_prefix}-profile"
  role = aws_iam_role.ansible_controller[0].name
  tags = merge(local.common_tags, {
    Name = "${local.ansible_resource_prefix}-profile"
  })
}
