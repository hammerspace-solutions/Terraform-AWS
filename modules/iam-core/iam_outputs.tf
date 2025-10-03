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
# modules/iam-core/iam_outputs.tf
#
# This file contains the variables that will be output
# -----------------------------------------------------------------------------

# Created role name (null when not created)

output "role_name" {
  value = try(
    one(aws_iam_role.ec2_ssm[*].name),
    null
  )
}

# Created role ARN (null when not created)

output "role_arn" {
  value = try(
    one(aws_iam_role.ec2_ssm[*].arn),
    null
  )
}

# Effective instance profile name:
# - If a name was provided to the module, pass it through
# - Otherwise, return the created one (or null if not present yet)

output "instance_profile_name" {
  value = (
    var.iam_profile_name != null
    ? var.iam_profile_name
    : try(one(aws_iam_instance_profile.ec2_ssm[*].name), null)
  )
}

# Ansible-specific profile name (null if not created)

output "ansible_profile_name" {
  value = try(
    one(aws_iam_instance_profile.ansible_controller[*].name),
    null
  )
}
