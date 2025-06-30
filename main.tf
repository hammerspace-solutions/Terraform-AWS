# Setup the provider

provider "aws" {
  region = var.region

  # If you plan on using the $HOME/.aws/credentials file, then please modify the
  # file local_override.tf in order to put in the profile variable.
  #
  # Refer to the README.md file for instructions.

  # --- The following line instructs the provider to not retry on retryable
  #     API errors.
  #
  # We want to fail on the first "InsufficientInstanceCapacity" and not have
  # it retries for many minutes to create an EC2 instance. Comment out the
  # next variable if you want the timeout value to take precedence.

  max_retries = 5
}

# -----------------------------------------------------------------------------
# Pre-flight checks to validate instance type existence before planning.
# This provides a "fail-fast" mechanism for invalid instance type variables.
# -----------------------------------------------------------------------------

check "anvil_instance_type_is_available" {
  data "aws_ec2_instance_type_offerings" "anvil_check" {
    provider = aws
    filter {
      name   = "instance-type"
      values = [var.hammerspace_anvil_instance_type]
    }
    filter {
      name   = "location"
      values = [var.availability_zone]
    }
    location_type = "availability-zone"
  }

  assert {
    condition     = length(data.aws_ec2_instance_type_offerings.anvil_check.instance_types) > 0
    error_message = "The specified Anvil instance type (${var.hammerspace_anvil_instance_type}) is not available in the selected Availability Zone (${var.availability_zone})."
  }
}

check "dsx_instance_type_is_available" {
  data "aws_ec2_instance_type_offerings" "dsx_check" {
    provider = aws
    filter {
      name   = "instance-type"
      values = [var.hammerspace_dsx_instance_type]
    }
    filter {
      name   = "location"
      values = [var.availability_zone]
    }
    location_type = "availability-zone"
  }

  assert {
    condition     = length(data.aws_ec2_instance_type_offerings.dsx_check.instance_types) > 0
    error_message = "The specified DSX instance type (${var.hammerspace_dsx_instance_type}) is not available in the selected Availability Zone (${var.availability_zone})."
  }
}

check "client_instance_type_is_available" {
  data "aws_ec2_instance_type_offerings" "client_check" {
    provider = aws
    filter {
      name   = "instance-type"
      values = [var.clients_instance_type]
    }
    filter {
      name   = "location"
      values = [var.availability_zone]
    }
    location_type = "availability-zone"
  }

  assert {
    condition     = length(data.aws_ec2_instance_type_offerings.client_check.instance_types) > 0
    error_message = "The specified Client instance type (${var.clients_instance_type}) is not available in the selected Availability Zone (${var.availability_zone})."
  }
}

check "storage_server_instance_type_is_available" {
  data "aws_ec2_instance_type_offerings" "storage_check" {
    provider = aws
    filter {
      name   = "instance-type"
      values = [var.storage_instance_type]
    }
    filter {
      name   = "location"
      values = [var.availability_zone]
    }
    location_type = "availability-zone"
  }

  assert {
    condition     = length(data.aws_ec2_instance_type_offerings.storage_check.instance_types) > 0
    error_message = "The specified Storage Server instance type (${var.storage_instance_type}) is not available in the selected Availability Zone (${var.availability_zone})."
  }
}

# -----------------------------------------------------------------------------
# On-Demand Capacity Reservations to guarantee availability before apply.
# -----------------------------------------------------------------------------

resource "aws_ec2_capacity_reservation" "anvil" {
  count = local.deploy_hammerspace && var.hammerspace_anvil_count > 0 ? 1 : 0

  instance_type     = var.hammerspace_anvil_instance_type
  instance_platform = "Linux/UNIX"
  availability_zone = var.availability_zone
  instance_count    = var.hammerspace_anvil_count
  tenancy           = "default"
  end_date_type     = "unlimited"
  tags              = merge(var.tags, { Name = "${var.project_name}-Anvil-Reservation" })

  timeouts {
    create = var.capacity_reservation_create_timeout
  }
}

resource "aws_ec2_capacity_reservation" "dsx" {
  count = local.deploy_hammerspace && var.hammerspace_dsx_count > 0 ? 1 : 0

  instance_type     = var.hammerspace_dsx_instance_type
  instance_platform = "Linux/UNIX"
  availability_zone = var.availability_zone
  instance_count    = var.hammerspace_dsx_count
  tenancy           = "default"
  end_date_type     = "unlimited"
  tags              = merge(var.tags, { Name = "${var.project_name}-DSX-Reservation" })

  timeouts {
    create = var.capacity_reservation_create_timeout
  }
}

resource "aws_ec2_capacity_reservation" "clients" {
  count = local.deploy_clients && var.clients_instance_count > 0 ? 1 : 0

  instance_type     = var.clients_instance_type
  instance_platform = "Linux/UNIX"
  availability_zone = var.availability_zone
  instance_count    = var.clients_instance_count
  tenancy           = "default"
  end_date_type     = "unlimited"
  tags              = merge(var.tags, { Name = "${var.project_name}-Clients-Reservation" })

  timeouts {
    create = var.capacity_reservation_create_timeout
  }
}

resource "aws_ec2_capacity_reservation" "storage" {
  count = local.deploy_storage && var.storage_instance_count > 0 ? 1 : 0

  instance_type     = var.storage_instance_type
  instance_platform = "Linux/UNIX"
  availability_zone = var.availability_zone
  instance_count    = var.storage_instance_count
  tenancy           = "default"
  end_date_type     = "unlimited"
  tags              = merge(var.tags, { Name = "${var.project_name}-Storage-Reservation" })

  timeouts {
    create = var.capacity_reservation_create_timeout
  }
}

# -----------------------------------------------------------------------------
# Resource and Module Definitions
# -----------------------------------------------------------------------------

# Conditionally create the placement group if a name is provided

resource "aws_placement_group" "this" {
  count    = var.placement_group_name != "" ? 1 : 0
  name     = var.placement_group_name
  strategy = var.placement_group_strategy
  tags     = var.tags
}

# Determine which components to deploy based on input list

locals {
  deploy_clients     = contains(var.deploy_components, "all") || contains(var.deploy_components, "clients")
  deploy_storage     = contains(var.deploy_components, "all") || contains(var.deploy_components, "storage")
  deploy_hammerspace = contains(var.deploy_components, "all") || contains(var.deploy_components, "hammerspace")
  deploy_ansible     = contains(var.deploy_components, "all") || contains(var.deploy_components, "ansible")

  # Combine all target nodes for Ansible

  all_ssh_nodes = concat(
    local.deploy_clients ? module.clients[0].instance_details : [],
    local.deploy_storage ? module.storage_servers[0].instance_details : []
  )

}

# Deploy the clients module if requested

module "clients" {
  count   = local.deploy_clients ? 1 : 0
  source  = "./modules/clients"

  # Pass the reservation ID to the module

  capacity_reservation_id = local.deploy_clients && var.clients_instance_count > 0 ? aws_ec2_capacity_reservation.clients[0].id : null

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

  depends_on = [module.hammerspace]
}

# Deploy the storage_servers module if requested

module "storage_servers" {
  count   = local.deploy_storage ? 1 : 0
  source  = "./modules/storage_servers"

  # Pass the reservation ID to the module

  capacity_reservation_id = local.deploy_storage && var.storage_instance_count > 0 ? aws_ec2_capacity_reservation.storage[0].id : null
  
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

  depends_on = [module.hammerspace]
}

# Deploy the Anvil and/or DSX if requested

module "hammerspace" {
  count   = local.deploy_hammerspace ? 1 : 0
  source  = "./modules/hammerspace"

  # Pass the reservation IDs to the module

  anvil_capacity_reservation_id = local.deploy_hammerspace && var.hammerspace_anvil_count > 0 ? aws_ec2_capacity_reservation.anvil[0].id : null
  dsx_capacity_reservation_id   = local.deploy_hammerspace && var.hammerspace_dsx_count > 0 ? aws_ec2_capacity_reservation.dsx[0].id : null

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

  ami                        = var.hammerspace_ami
  iam_admin_group_id         = var.hammerspace_iam_admin_group_id
  profile_id                 = var.hammerspace_profile_id
  anvil_security_group_id    = var.hammerspace_anvil_security_group_id
  dsx_security_group_id      = var.hammerspace_dsx_security_group_id
  anvil_count                = var.hammerspace_anvil_count
  sa_anvil_destruction       = var.hammerspace_sa_anvil_destruction
  anvil_type                 = var.hammerspace_anvil_instance_type
  anvil_meta_disk_size       = var.hammerspace_anvil_meta_disk_size
  anvil_meta_disk_type       = var.hammerspace_anvil_meta_disk_type
  anvil_meta_disk_iops       = var.hammerspace_anvil_meta_disk_iops
  anvil_meta_disk_throughput = var.hammerspace_anvil_meta_disk_throughput
  dsx_count                  = var.hammerspace_dsx_count
  dsx_type                   = var.hammerspace_dsx_instance_type
  dsx_ebs_size               = var.hammerspace_dsx_ebs_size
  dsx_ebs_type               = var.hammerspace_dsx_ebs_type
  dsx_ebs_iops               = var.hammerspace_dsx_ebs_iops
  dsx_ebs_throughput         = var.hammerspace_dsx_ebs_throughput
  dsx_ebs_count              = var.hammerspace_dsx_ebs_count
  dsx_add_vols               = var.hammerspace_dsx_add_vols
}

# Deploy the Ansible module if requested

module "ansible" {
  count   = local.deploy_ansible ? 1 : 0
  source  = "./modules/ansible"

  mgmt_ip           = flatten(module.hammerspace[*].management_ip)
  anvil_instances   = flatten(module.hammerspace[*].anvil_instances)
  storage_instances = flatten(module.storage_servers[*].instance_details)

  # Global Variables for Ansible configuration

  region               = var.region
  availability_zone    = var.availability_zone
  vpc_id               = var.vpc_id
  subnet_id            = var.subnet_id
  key_name             = var.key_name
  tags                 = var.tags
  project_name         = var.project_name
  ssh_keys_dir         = var.ssh_keys_dir
  placement_group_name = var.placement_group_name

  # Ansible specific variables

  instance_count   = var.ansible_instance_count
  ami              = var.ansible_ami
  instance_type    = var.ansible_instance_type
  boot_volume_size = var.ansible_boot_volume_size
  boot_volume_type = var.ansible_boot_volume_type
  user_data        = var.ansible_user_data
  target_user      = var.ansible_target_user
  volume_group_name = var.volume_group_name
  share_name       = var.share_name

  # Pass the new variables needed by the ansible_ssh_setup.sh script

  target_nodes_json = jsonencode(local.all_ssh_nodes)
  admin_private_key = file("./modules/ansible/ansible_admin_key") # Reads the private key from a file

  depends_on = [
    module.clients,
    module.storage_servers,
    module.hammerspace
  ]
}
