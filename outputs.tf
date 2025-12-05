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
  value       = "2025.11.10-896c9f2"
}

output "client_instances" {
  description = "Client instance details (non-sensitive)."
  value       = local.deploy_clients ? module.clients[*].instance_details : null
}

output "storage_instances" {
  description = "Storage instance details (non-sensitive)."
  value       = local.deploy_storage ? module.storage_servers[*].instance_details : null
}

output "hammerspace_anvil" {
  description = "Hammerspace Anvil details"
  value       = local.deploy_hammerspace ? module.hammerspace[*].anvil_instances : null
  sensitive   = true
}

output "hammerspace_dsx" {
  description = "Hammerspace DSX details"
  sensitive   = false
  value       = local.deploy_hammerspace ? module.hammerspace[*].dsx_instances : null
}

output "hammerspace_mgmt_ip" {
  description = "Hammerspace Mgmt IP"
  value       = local.deploy_hammerspace ? module.hammerspace[*].management_ip : null
}

output "hammerspace_mgmt_url" {
  description = "Hammerspace Mgmt URL"
  value       = local.deploy_hammerspace ? module.hammerspace[*].management_url : null
}

output "hammerspace_dsx_private_ips" {
  description = "A list of private IP addresses for the Hammerspace DSX instances."
  value       = local.deploy_hammerspace ? module.hammerspace[*].dsx_private_ips : null
}

output "hammerspace_ha_lb" {
  description = "The DNS name of the HA Anvil load balancer. This is only used for public IP"
  value       = local.deploy_hammerspace ? one(module.hammerspace[*].anvil_ha_load_balancer_dns_name) : null
}

output "ecgroup_nodes" {
  description = "ECGroup node details"
  sensitive   = false
  value       = local.deploy_ecgroup ? module.ecgroup[*].nodes : null
}

output "ecgroup_metadata_array" {
  description = "ECGroup metadata array"
  sensitive   = true
  value       = local.deploy_ecgroup ? module.ecgroup[*].metadata_array : null
}

output "ecgroup_storage_array" {
  description = "ECGroup storage array"
  sensitive   = false
  value       = local.deploy_ecgroup ? module.ecgroup[*].storage_array : null
}

output "ansible_details" {
  description = "Ansible configuration details"
  value       = module.ansible[*].ansible_details
}

# -----------------------------------------------------------------------------
# Amazon MQ / RabbitMQ outputs (from module "amazon_mq")
# These will be null when MQ is not deployed (deploy_components excludes "mq")
# -----------------------------------------------------------------------------

output "amazonemq_broker_id" {
  description = "ID of the Amazon MQ RabbitMQ broker"
  value       = local.deploy_mq ? module.amazon_mq[0].amazonmq_broker_id : null
  sensitive   = true
}

output "amazonmq_broker_arn" {
  description = "ARN of the Amazon MQ RabbitMQ broker"
  value       = local.deploy_mq ? module.amazon_mq[0].amazonmq_broker_arn : null
  sensitive   = true
}

output "amazonmq_security_group_id" {
  description = "Security group ID attached to the RabbitMQ broker"
  value       = local.deploy_mq ? module.amazon_mq[0].amazonmq_security_group_id : null
  sensitive   = true
}

# Primary AMQPS endpoint (what your shovels will use)
output "amazonmq_amqps_endpoint" {
  description = "Primary AMQPS endpoint for the RabbitMQ broker"
  value       = local.deploy_mq ? module.amazon_mq[0].amazonmq_amqps_endpoint : null
}

# (Optional) Web console URL
output "amazonmq_console_url" {
  description = "RabbitMQ management console URL"
  value       = local.deploy_mq ? module.amazon_mq[0].amazonmq_console_url : null
}

output "amazonmq_hosted_zone_id" {
  description = "Route 53 private hosted zone ID created for RabbitMQ (if any)"
  value       = local.deploy_mq ? module.amazon_mq[0].hosted_zone_id : null
}
