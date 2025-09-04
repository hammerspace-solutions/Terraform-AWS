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
# modules/iam-core/iam_main.tf
#
# This file contains the main logic for setting up IAM roles and permissions.
# -----------------------------------------------------------------------------

data "aws_partition" "current" {}

locals {
  resource_prefix = "${var.common_config.project_name}-ssm"
  common_tags	  = "${var.common_config.tags}"
}

resource "aws_iam_role" "ec2_ssm" {
  count = var.iam_profile_name == null ? 1 : 0
  
  name = "${local.resource_prefix}-role"
  path = var.role_path
  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-role"
  })

  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },   # use dns_suffix if you need Gov/China
      Action    = "sts:AssumeRole"                     # <- colon (correct)
    }]
  })
}

# Base SSM permissions

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_ssm[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Optional extras (CloudWatch Agent, S3 access, etc.)

resource "aws_iam_role_policy_attachment" "extra" {
  for_each   = toset(var.extra_managed_policy_arns)
  role       = aws_iam_role.ec2_ssm[0].name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "${local.resource_prefix}-profile"
  role = aws_iam_role.ec2_ssm[0].name
  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-profile"
  })
}
