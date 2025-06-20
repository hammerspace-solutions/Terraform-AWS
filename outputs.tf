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

# NEW output for the list of DSX private IPs
output "hammerspace_dsx_private_ips" {
  description = "A list of private IP addresses for the Hammerspace DSX instances."
  value       = module.hammerspace[*].dsx_private_ips
}
