# modules/storage_servers/examples/main.tf

provider "aws" {
  region = var.region
}

# Define all the variables this test example might receive
variable "region" {}
variable "project_name" {}
variable "vpc_id" {}
variable "subnet_id" {}
variable "storage_ami" {}
variable "storage_instance_type" {
  default = "t3.medium"
}
variable "storage_instance_count" {
  type    = number
  default = 1
}
variable "storage_ebs_count" {
  type = number
}
variable "storage_raid_level" {
  type = string
}
variable "storage_user_data" {
  type = string
}
# ADDED: A variable to accept the public key material from the Go test
variable "ssh_public_key" {
  description = "The public key material for the temporary SSH key."
  type        = string
}

# Create a temporary key pair for this test run
resource "aws_key_pair" "test_key" {
  key_name   = "${var.project_name}-key"
  public_key = var.ssh_public_key
}

# Look up the AZ from the provided subnet to ensure a match
data "aws_subnet" "test_subnet" {
  id = var.subnet_id
}

# Call the storage_servers module we want to test
module "storage_servers" {
  source = "../" // Points to the storage_servers module root

  # Pass variables to the module
  instance_count    = var.storage_instance_count
  ami               = var.storage_ami
  instance_type     = var.storage_instance_type
  raid_level        = var.storage_raid_level
  ebs_count         = var.storage_ebs_count
  project_name      = var.project_name
  region            = var.region
  availability_zone = data.aws_subnet.test_subnet.availability_zone
  vpc_id            = var.vpc_id
  subnet_id         = var.subnet_id
  key_name          = aws_key_pair.test_key.key_name # Use the newly created key pair
  user_data         = var.storage_user_data

  # Use sensible defaults for other required variables
  tags                    = {}
  ssh_keys_dir            = ""
  boot_volume_size        = 100
  boot_volume_type        = "gp3"
  ebs_size                = 10
  ebs_type                = "gp3"
  target_user             = "ubuntu"
  capacity_reservation_id = null
}

# Output the results for validation
output "storage_instances" {
  description = "The details of the created storage instances."
  value       = module.storage_servers.instance_details
}

output "region" {
  description = "The AWS region where resources were deployed."
  value       = var.region
}

# ADDED: Output the public IP for the SSH connection
output "public_ip" {
  description = "The public IP of the first storage server."
  value       = module.storage_servers.instance_details[0].public_ip
}
