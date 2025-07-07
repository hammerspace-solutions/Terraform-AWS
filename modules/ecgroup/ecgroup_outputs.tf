output "nodes" {
  description = "Details about ecgroup nodes (ID, Name, IP)."
  value = [
    for i in aws_instance.nodes : {
      id         = i.id
      private_ip = i.private_ip
      name       = i.tags.Name
    }
  ]
}

output "metadata_array" {
  description = "ECGroup metadata array."
  value       = "NVME_${var.metadata_ebs_size / 1024}T"
}

output "storage_array" {
  description = "ECGroup storage array."
  value       = "NVME_${var.storage_ebs_size / 1024}T"
}