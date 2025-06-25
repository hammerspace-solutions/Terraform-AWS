# modules/clients/examples/main.tf

# This provider block is used by the test.
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
  type    = number # Ensure correct type
  default = 1
}

# This data source finds an available AZ in the selected region for the test.
data "aws_availability_zones" "available" {
  state = "available"
}

# This is the corrected module block.
# Notice the variable names now match what modules/clients/clients_variables.tf expects.
# e.g., 'ami' instead of 'clients_ami'.
module "clients" {
  source = "../" // Points to the module root

  # Pass the correct, unprefixed variables to the module
  instance_count    = var.clients_instance_count
  ami               = var.clients_ami
  instance_type     = var.clients_instance_type
  
  # Pass through global/shared variables
  project_name      = var.project_name
  region            = var.region
  availability_zone = data.aws_availability_zones.available.names[0]
  vpc_id            = var.vpc_id
  subnet_id         = var.subnet_id
  key_name          = var.key_name

  tags                 = {}
  ssh_keys_dir         = "./ssh_keys" # Placeholder, not used if user_data is blank
  boot_volume_size     = 100
  boot_volume_type     = "gp3"
  ebs_count            = 1
  ebs_size             = 10
  ebs_type             = "gp3"
  user_data            = ""
  target_user          = "ubuntu"
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
