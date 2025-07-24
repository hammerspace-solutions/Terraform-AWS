# modules/clients/examples/main.tf

provider "aws" {
  region = var.region
}

# These are the variables that the test will provide values for.
variable "region" {}
variable "project_name" {}
variable "vpc_id" {}
variable "subnet_id" {}
variable "key_name" {}
variable "clients_ami" {}
variable "clients_instance_type" {
  default = "t3.medium"
}
variable "clients_instance_count" {
  type    = number
  default = 1
}
variable "ebs_count" {
  type    = number
  default = 1
}
variable "boot_volume_type" {
  type    = string
  default = "gp3"
}
variable "ebs_type" {
  type    = string
  default = "gp3"
}


# --- THIS IS THE CORRECT FIX ---
# Instead of guessing the AZ, we look up the details of the provided subnet
# and use its actual availability_zone attribute. This guarantees a match.
data "aws_subnet" "test_subnet" {
  id = var.subnet_id
}


# This module block calls the clients module for testing.
module "clients" {
  source = "../" // Correctly points to the parent 'clients' module directory

  # Pass the required unprefixed variables to the module.
  instance_count    = var.clients_instance_count
  ami               = var.clients_ami
  instance_type     = var.clients_instance_type
  
  # Pass through global/shared variables.
  project_name      = var.project_name
  region            = var.region
  availability_zone = data.aws_subnet.test_subnet.availability_zone # Use the AZ from the subnet
  vpc_id            = var.vpc_id
  subnet_id         = var.subnet_id
  key_name          = var.key_name

  # Provide default values for other required module arguments.
  tags                 = {}
  ssh_keys_dir         = ""
  boot_volume_size     = 100
  boot_volume_type     = var.boot_volume_type
  ebs_count            = var.ebs_count
  ebs_size             = 10
  ebs_type             = var.ebs_type
  user_data            = ""
  target_user          = "ubuntu"
  
  # For this isolated test, we do not use a capacity reservation.
  capacity_reservation_id = null
}


# Output the results for validation by the Go test.
output "client_instances" {
  description = "The details of the created client instances."
  value       = module.clients.instance_details
}

output "region" {
  description = "The AWS region where resources were deployed."
  value       = var.region
}
