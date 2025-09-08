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
# modules/ansible/ansible_outputs.tf
#
# This file defines the outputs for the Ansible module.
# -----------------------------------------------------------------------------

output "ansible_details" {
  description = "Per-instance details for Ansible hosts"
  value = [
    for i in range(var.instance_count) : {
      name       = try(aws_instance.ansible[i].tags.Name, null)
      id         = aws_instance.ansible[i].id
      az         = aws_instance.ansible[i].availability_zone
      private_ip = aws_instance.ansible[i].private_ip

      # Prefer the allocated EIP; fall back to instance public_ip if you ever enable it,
      # else report null when no public address is expected.
      
      public_ip = (
        var.assign_public_ip
        ? coalesce(
            try(aws_eip.ansible[i].public_ip, ""),
            try(aws_instance.ansible[i].public_ip, "")
          )
        : null
      )

      ssm_association_id = (
        var.use_ssm_bootstrap
        ? try(aws_ssm_association.ansible_bootstrap[i].association_id, null)
        : null
      )
    }
  ]
}
