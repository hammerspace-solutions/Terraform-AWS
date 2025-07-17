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

locals {
  # Raw values in GiB
  metadata_size_gib = var.metadata_ebs_size
  storage_size_gib  = var.storage_ebs_size

  # Convert sizes
  metadata_size_tb = var.metadata_ebs_size / 1024
  metadata_size_pb = var.metadata_ebs_size / 1048576
  storage_size_tb  = var.storage_ebs_size / 1024
  storage_size_pb  = var.storage_ebs_size / 1048576

  # Rounded values
  metadata_rounded_gib = floor(local.metadata_size_gib + 0.5)
  metadata_rounded_tb  = floor(local.metadata_size_tb * 10 + 0.5) / 10
  metadata_rounded_pb  = floor(local.metadata_size_pb * 10 + 0.5) / 10

  storage_rounded_gib = floor(local.storage_size_gib + 0.5)
  storage_rounded_tb  = floor(local.storage_size_tb * 10 + 0.5) / 10
  storage_rounded_pb  = floor(local.storage_size_pb * 10 + 0.5) / 10
}

output "metadata_array" {
  description = "ECGroup metadata array."
  value = (
    var.metadata_ebs_size < 1024 ? "NVME_${local.metadata_rounded_gib}G" :
    var.metadata_ebs_size < 1048576 ? "NVME_${local.metadata_rounded_tb}T" :
    "NVME_${local.metadata_rounded_pb}P"
  )
}

output "storage_array" {
  description = "ECGroup storage array."
  value = (
    var.storage_ebs_size < 1024 ? "NVME_${local.storage_rounded_gib}G" :
    var.storage_ebs_size < 1048576 ? "NVME_${local.storage_rounded_tb}T" :
    "NVME_${local.storage_rounded_pb}P"
  )
}
