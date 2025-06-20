# Setup the provider

provider "aws" {
  region = var.region

  # If you plan on using the $HOME/.aws/credentials file, then please modify the
  # file local_override.tf in order to put in the profile variable.
  #
  # Refer to the README.md file for instructions.
}

# Conditionally create the placement group if a name is provided

resource "aws_placement_group" "this" {
  count = var.placement_group_name != "" ? 1 : 0

  name     = var.placement_group_name
  strategy = var.placement_group_strategy
  tags     = var.tags
}

# Determine which components to deploy based on input list

locals {
  deploy_clients     = contains(var.deploy_components, "all") || contains(var.deploy_components, "clients")
  deploy_storage     = contains(var.deploy_components, "all") || contains(var.deploy_components, "storage")
  deploy_hammerspace = contains(var.deploy_components, "all") || contains(var.deploy_components, "hammerspace")
}

# Deploy the clients module if requested

module "clients" {
  count  = local.deploy_clients ? 1 : 0
  source = "./modules/clients"

  # Global variables
  region               = var.region
  availability_zone    = var.availability_zone
  vpc_id               = var.vpc_id
  subnet_id            = var.subnet_id
  key_name             = var.key_name
  tags                 = var.tags
  project_name         = var.project_name
  ssh_keys_dir         = var.ssh_keys_dir
  placement_group_name = var.placement_group_name != "" ? aws_placement_group.this[0].name : ""

  # Client-specific variables
  instance_count   = var.clients_instance_count
  ami              = var.clients_ami
  instance_type    = var.clients_instance_type
  boot_volume_size = var.clients_boot_volume_size
  boot_volume_type = var.clients_boot_volume_type
  ebs_count        = var.clients_ebs_count
  ebs_size         = var.clients_ebs_size
  ebs_type         = var.clients_ebs_type
  ebs_throughput   = var.clients_ebs_throughput
  ebs_iops         = var.clients_ebs_iops
  user_data        = var.clients_user_data
  target_user      = var.clients_target_user
}

# Deploy the storage_servers module if requested

module "storage_servers" {
  count  = local.deploy_storage ? 1 : 0
  source = "./modules/storage_servers"

  # Global variables
  region               = var.region
  availability_zone    = var.availability_zone
  vpc_id               = var.vpc_id
  subnet_id            = var.subnet_id
  key_name             = var.key_name
  tags                 = var.tags
  project_name         = var.project_name
  ssh_keys_dir         = var.ssh_keys_dir
  placement_group_name = var.placement_group_name != "" ? aws_placement_group.this[0].name : ""

  # Storage-specific variables
  instance_count   = var.storage_instance_count
  ami              = var.storage_ami
  instance_type    = var.storage_instance_type
  boot_volume_size = var.storage_boot_volume_size
  boot_volume_type = var.storage_boot_volume_type
  raid_level       = var.storage_raid_level
  ebs_count        = var.storage_ebs_count
  ebs_size         = var.storage_ebs_size
  ebs_type         = var.storage_ebs_type
  ebs_throughput   = var.storage_ebs_throughput
  ebs_iops         = var.storage_ebs_iops
  user_data        = var.storage_user_data
  target_user      = var.storage_target_user
}

# Deploy the Anvil and/or DSX if requested

module "hammerspace" {
  count  = local.deploy_hammerspace ? 1 : 0
  source = "./modules/hammerspace"

  # Global variables
  region               = var.region
  availability_zone    = var.availability_zone
  vpc_id               = var.vpc_id
  subnet_id            = var.subnet_id
  key_name             = var.key_name
  tags                 = var.tags
  project_name         = var.project_name
  placement_group_name = var.placement_group_name != "" ? aws_placement_group.this[0].name : ""

  # Hammerspace-specific variables
  ami                                  = var.hammerspace_ami
  iam_admin_group_id                   = var.hammerspace_iam_admin_group_id
  profile_id                           = var.hammerspace_profile_id
  anvil_security_group_id              = var.hammerspace_anvil_security_group_id
  dsx_security_group_id                = var.hammerspace_dsx_security_group_id

  anvil_count                          = var.hammerspace_anvil_count
  sa_anvil_destruction   	       = var.hammerspace_sa_anvil_destruction
  anvil_type                           = var.hammerspace_anvil_instance_type
  anvil_meta_disk_size                 = var.hammerspace_anvil_meta_disk_size
  anvil_meta_disk_type                 = var.hammerspace_anvil_meta_disk_type
  anvil_meta_disk_iops                 = var.hammerspace_anvil_meta_disk_iops
  anvil_meta_disk_throughput           = var.hammerspace_anvil_meta_disk_throughput

  dsx_count                            = var.hammerspace_dsx_count
  dsx_type                             = var.hammerspace_dsx_instance_type
  dsx_ebs_size                         = var.hammerspace_dsx_ebs_size
  dsx_ebs_type                         = var.hammerspace_dsx_ebs_type
  dsx_ebs_iops                         = var.hammerspace_dsx_ebs_iops
  dsx_ebs_throughput                   = var.hammerspace_dsx_ebs_throughput
  dsx_ebs_count                        = var.hammerspace_dsx_ebs_count
  dsx_add_vols                         = var.hammerspace_dsx_add_vols
}
