output "instance_details" {
  description = "A list of non-sensitive details for Ansible instances (ID, Name, IP)."
  value = [
    for i in aws_instance.this : {
      id         = i.id
      private_ip = i.private_ip
      name       = i.tags.Name
    }
  ]
}
