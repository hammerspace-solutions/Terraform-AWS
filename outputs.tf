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
# outputs.tf
#
# Terraform file to output results of any deployment
# -----------------------------------------------------------------------------

output "terraform_project_version" {
  description = "The version of the Terraform-AWS project configuration."
  value       = "2025.07.02"
}

output "client_instances" {
  description = "Client instance details (non-sensitive)."
  value       = module.clients[*].instance_details
}

output "client_ebs_volumes" {
  description = "Client EBS volume details (sensitive)."
  value       = module.clients[*].ebs_volume_details
  sensitive   = true
}

output "storage_instances" {
  description = "Storage instance details (non-sensitive)."
  value       = module.storage_servers[*].instance_details
}

output "storage_ebs_volumes" {
  description = "Storage EBS volume details (sensitive)."
  value       = module.storage_servers[*].ebs_volume_details
  sensitive   = true
}

output "hammerspace_anvil" {
  description = "Hammerspace Anvil details"
  value       = module.hammerspace[*].anvil_instances
  sensitive   = true
}

output "hammerspace_dsx" {
  description = "Hammerspace DSX details"
  sensitive   = true # <-- ADDED
  value       = module.hammerspace[*].dsx_instances
}

output "hammerspace_mgmt_ip" {
  description = "Hammerspace Mgmt IP"
  value       = module.hammerspace[*].management_ip
}

output "hammerspace_mgmt_url" {
  description = "Hammerspace Mgmt URL"
  value       = module.hammerspace[*].management_url
}

output "hammerspace_dsx_private_ips" {
  description = "A list of private IP addresses for the Hammerspace DSX instances."
  value       = module.hammerspace[*].dsx_private_ips
}

output "ansible_details" {
  description = "Ansible configuration details"
  value = module.ansible[*].instance_details
}
