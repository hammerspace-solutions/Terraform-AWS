output "instance_details" {
  description = "A list of non-sensitive details for storage instances (ID, Name, IP)."
  value = [
    for i in aws_instance.this : {
      id         = i.id
      private_ip = i.private_ip
      name       = i.tags.Name
    }
  ]
}

output "ebs_volume_details" {
  description = "A list of sensitive EBS volume details for storage instances."
  sensitive   = true
  value = [
    for v in aws_ebs_volume.this : {
      id   = v.id
      size = v.size
      type = v.type
    }
  ]
}
