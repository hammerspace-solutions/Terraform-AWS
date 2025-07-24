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
variable "ssh_public_key" {
  description = "The public key material for the temporary SSH key."
  type        = string
}
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
# Variable to control the test-specific firewall rules
variable "allow_test_ingress" {
  description = "If true, the module will open SSH and ICMP ports for testing."
  type        = bool
  default     = false
}

# Create a temporary key pair for this test run
resource "aws_key_pair" "test_key" {
  key_name   = "${var.project_name}-key"
  public_key = var.ssh_public_key
}

# An Elastic IP ensures the test instance has a reliable public IP address.
resource "aws_eip" "test_eip" {
  count  = var.storage_instance_count > 0 ? 1 : 0
  domain = "vpc"
}

# Look up the AZ from the provided subnet to ensure a match
data "aws_subnet" "test_subnet" {
  id = var.subnet_id
}

# Call the storage_servers module we want to test
module "storage_servers" {
  source = "../" // Points to the storage_servers module root

  # Pass test-specific values
  allow_test_ingress = var.allow_test_ingress # This will be true during the test
  key_name           = aws_key_pair.test_key.key_name

  # Pass other required variables
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
  user_data         = var.storage_user_data

  # Use module defaults for the rest
  tags                    = {}
  ssh_keys_dir            = ""
  boot_volume_size        = 100
  boot_volume_type        = "gp3"
  ebs_size                = 10
  ebs_type                = "gp3"
  target_user             = "ubuntu"
  capacity_reservation_id = null
}

# Associate the Elastic IP with our test instance after it has been created.
resource "aws_eip_association" "test_eip_assoc" {
  count = var.storage_instance_count > 0 ? 1 : 0

  instance_id   = module.storage_servers.instance_details[0].id
  allocation_id = aws_eip.test_eip[0].id
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

output "public_ip" {
  description = "The public IP of the first storage server."
  value       = var.storage_instance_count > 0 ? aws_eip.test_eip[0].public_ip : null
}
