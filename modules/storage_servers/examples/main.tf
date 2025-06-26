# modules/storage_servers/examples/main.tf

provider "aws" {
  region = var.region
}

# Define all the variables this test example might receive
variable "region" {}
variable "project_name" {}
variable "vpc_id" {}
variable "subnet_id" {}
variable "key_name" {}
variable "storage_ami" {}
variable "storage_instance_type" {
  default = "t3.medium"
}
variable "storage_instance_count" {
  type    = number
  default = 1
}
variable "storage_ebs_count" {
  type    = number
}
variable "storage_raid_level" {
  type = string
}

# Look up the AZ from the provided subnet to ensure a match
data "aws_subnet" "test_subnet" {
  id = var.subnet_id
}

# Call the storage_servers module we want to test
module "storage_servers" {
  source = "../" // Points to the storage_servers module root

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
  key_name          = var.key_name

  # Use sensible defaults for other required variables for the test
  tags                 = {}
  ssh_keys_dir         = ""
  boot_volume_size     = 100
  boot_volume_type     = "gp3"
  ebs_size             = 10
  ebs_type             = "gp3"
  user_data            = var.storage_user_data
  target_user          = "ubuntu"
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
# modules/storage_servers/examples/main.tf

provider "aws" {
  region = var.region
}

# Define all the variables this test example might receive
variable "region" {}
variable "project_name" {}
variable "vpc_id" {}
variable "subnet_id" {}
variable "key_name" {}
variable "storage_ami" {}
variable "storage_instance_type" {
  default = "t3.medium"
}
variable "storage_instance_count" {
  type    = number
  default = 1
}
variable "storage_ebs_count" {
  type    = number
}
variable "storage_raid_level" {
  type = string
}

# Look up the AZ from the provided subnet to ensure a match
data "aws_subnet" "test_subnet" {
  id = var.subnet_id
}

# Call the storage_servers module we want to test
module "storage_servers" {
  source = "../" // Points to the storage_servers module root

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
  key_name          = var.key_name

  # Use sensible defaults for other required variables for the test
  tags                 = {}
  ssh_keys_dir         = ""
  boot_volume_size     = 100
  boot_volume_type     = "gp3"
  ebs_size             = 10
  ebs_type             = "gp3"
  user_data            = "../../../templates/storage_server_ubuntu.sh"
  target_user          = "ubuntu"
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
