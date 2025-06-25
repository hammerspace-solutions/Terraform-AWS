# modules/clients/examples/main.tf

provider "aws" {
  region = var.region
}

# Define the variables this example needs
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
  default = 1
}

# Call the clients module we want to test
module "clients" {
  source = "../../" // Go up two directories to the module's root

  project_name         = var.project_name
  region               = var.region
  availability_zone    = data.aws_availability_zones.available.names[0]
  vpc_id               = var.vpc_id
  subnet_id            = var.subnet_id
  key_name             = var.key_name
  clients_ami          = var.clients_ami
  clients_instance_type  = var.clients_instance_type
  clients_instance_count = var.clients_instance_count
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Output the results for validation
output "client_instances" {
  value = module.clients.instance_details
}

output "region" {
  value = var.region
}
