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
# 15-iam-core.tf
# Creates a shared EC2 IAM role + instance profile for Hammerspace and
# attaches the required inline permissions documented by Hammerspace.
# -----------------------------------------------------------------------------

data "aws_partition" "current" {}

# Hammerspace required inline policies
data "aws_iam_policy_document" "hammerspace_required" {
  # SSH public keys from IAM users
  statement {
    sid     = "SSHKeyAccess"
    effect  = "Allow"
    actions = [
      "iam:ListSSHPublicKeys",
      "iam:GetSSHPublicKey"
    ]
    resources = ["arn:${data.aws_partition.current.partition}:iam::*:user/*"]
  }

  # Group lookup for IAM-based SSH access control
  statement {
    sid     = "SSHGroupLookup"
    effect  = "Allow"
    actions = ["iam:GetGroup"]
    resources = ["*"]
  }

  # HA partner discovery
  statement {
    sid     = "HAInstanceDiscovery"
    effect  = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceAttribute",
      "ec2:DescribeTags"
    ]
    resources = ["*"]
  }

  # Floating IP failover
  statement {
    sid     = "HAFloatingIP"
    effect  = "Allow"
    actions = [
      "ec2:AssignPrivateIpAddresses",
      "ec2:UnassignPrivateIpAddresses"
    ]
    resources = ["*"]
  }

  # Marketplace metering (for Marketplace AMIs)
  statement {
    sid     = "MarketplaceMetering"
    effect  = "Allow"
    actions = ["aws-marketplace:MeterUsage"]
    resources = ["*"]
  }
}

module "iam_core_hammerspace" {
  source       = "./modules/iam-core"
  project_name = var.project_name
  role_name    = "${var.project_name}-hammerspace"

  enable_ssm              = true
  enable_cloudwatch_agent = true

  # attach required inline policy as a single JSON doc
  inline_policies = {
    "hammerspace-required" = data.aws_iam_policy_document.hammerspace_required.json
  }
}
