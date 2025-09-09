# Copyright (c) 2025 Hammerspace, Inc
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# -----------------------------------------------------------------------------
# main.tf
#
# This is the root module for the Terraform-AWS project. It defines the
# providers, pre-flight validations, and calls the component modules.
# -----------------------------------------------------------------------------

# Setup the provider

provider "aws" {
  region      = var.region
  max_retries = 5
}

# -----------------------------------------------------------------------------
# Pre-flight Validation for Networking
# -----------------------------------------------------------------------------

data "aws_vpc" "validation" {
  id = var.vpc_id
}

data "aws_subnet" "private_subnet" {
  id = var.subnet_id
}

# Define the public subnet data source. It will only be instantiated (count = 1)
# if var.public_subnet_id is not null. Otherwise, it will be an empty list (count = 0).

data "aws_subnet" "public_subnet_data" {
  count = var.public_subnet_id != "" ? 1 : 0
  id    = var.public_subnet_id
}

# These group of checks make sure that the AMIs exist in the region
# where you are trying to start them up. This only gets the data,
# it does not trigger the check and error message. That comes later.

# Ansible AMI Exists?

data "aws_ami" "ansible_ami_check" {
  count = local.deploy_ansible ? 1 : 0

  provider    = aws
  most_recent = true
  owners      = distinct(compact(concat(["self", "amazon", "aws-marketplace"], var.custom_ami_owner_ids)))

  filter {
    name   = "image-id"
    values = [var.ansible_ami]
  }
}

# Client AMI Exists?

data "aws_ami" "client_ami_check" {
  count = local.deploy_clients ? 1 : 0

  provider    = aws
  most_recent = true
  owners      = distinct(compact(concat(["self", "amazon", "aws-marketplace"], var.custom_ami_owner_ids)))

  filter {
    name   = "image-id"
    values = [var.clients_ami]
  }
}

# ECGroup AMI Exists?

data "aws_ami" "ecgroup_node_ami_check" {
  count = local.deploy_ecgroup ? 1 : 0

  provider    = aws
  most_recent = true
  owners      = ["self", "amazon"]

  filter {
    name   = "image-id"
    values = [local.select_ecgroup_ami_for_region]
  }
}

# Hammerspace Anvil and DSX share an AMI

data "aws_ami" "hammerspace_ami_check" {
  count = local.deploy_hammerspace ? 1 : 0

  provider    = aws
  most_recent = true
  owners      = distinct(compact(concat(["self", "amazon", "aws-marketplace"], var.custom_ami_owner_ids)))

  filter {
    name   = "image-id"
    values = [var.hammerspace_ami]
  }
}

# Storage Server AMI Exists?

data "aws_ami" "storage_ami_check" {
  count = local.deploy_storage ? 1 : 0

  provider    = aws
  most_recent = true
  owners      = distinct(compact(concat(["self", "amazon", "aws-marketplace"], var.custom_ami_owner_ids)))

  filter {
    name   = "image-id"
    values = [var.storage_ami]
  }
}

# -----------------------------------------------------------------------------
# Pre-flight check that the subnet is in the vpc
# -----------------------------------------------------------------------------

check "vpc_and_subnet_validation" {
  assert {
    condition     = data.aws_subnet.private_subnet.vpc_id == data.aws_vpc.validation.id
    error_message = "Validation Error: The provided subnet (ID: ${var.subnet_id}) does not belong to the provided VPC (ID: ${var.vpc_id})."
  }
}

check "public_subnet_validation" {
  assert {
    condition     = var.public_subnet_id == "" || (data.aws_subnet.public_subnet_data[0].vpc_id == data.aws_vpc.validation.id)
    error_message = "Validation Error: The provided public_subnet_id (ID: ${var.public_subnet_id}) does not belong to the provided VPC (ID: ${var.vpc_id})."
  }
}

# -----------------------------------------------------------------------------
# Pre-flight checks for instance type existence.
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
      values = [data.aws_subnet.private_subnet.availability_zone]
    }
    location_type = "availability-zone"
  }
  assert {
    condition     = length(data.aws_ec2_instance_type_offerings.anvil_check.instance_types) > 0
    error_message = "The specified Anvil instance type (${var.hammerspace_anvil_instance_type}) is not available in the selected Availability Zone (${data.aws_subnet.private_subnet.availability_zone})."
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
      values = [data.aws_subnet.private_subnet.availability_zone]
    }
    location_type = "availability-zone"
  }
  assert {
    condition     = length(data.aws_ec2_instance_type_offerings.dsx_check.instance_types) > 0
    error_message = "The specified DSX instance type (${var.hammerspace_dsx_instance_type}) is not available in the selected Availability Zone (${data.aws_subnet.private_subnet.availability_zone})."
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
      values = [data.aws_subnet.private_subnet.availability_zone]
    }
    location_type = "availability-zone"
  }
  assert {
    condition     = length(data.aws_ec2_instance_type_offerings.client_check.instance_types) > 0
    error_message = "The specified Client instance type (${var.clients_instance_type}) is not available in the selected Availability Zone (${data.aws_subnet.private_subnet.availability_zone})."
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
      values = [data.aws_subnet.private_subnet.availability_zone]
    }
    location_type = "availability-zone"
  }
  assert {
    condition     = length(data.aws_ec2_instance_type_offerings.storage_check.instance_types) > 0
    error_message = "The specified Storage Server instance type (${var.storage_instance_type}) is not available in the selected Availability Zone (${data.aws_subnet.private_subnet.availability_zone})."
  }
}

# ECGroup

check "ecgroup_node_instance_type_is_available" {
  data "aws_ec2_instance_type_offerings" "ecgroup_node_check" {
    provider = aws
    filter {
      name   = "instance-type"
      values = [var.ecgroup_instance_type]
    }
    filter {
      name   = "location"
      values = [data.aws_subnet.private_subnet.availability_zone]
    }
    location_type = "availability-zone"
  }

  assert {
    condition     = length(data.aws_ec2_instance_type_offerings.ecgroup_node_check.instance_types) > 0
    error_message = "The specified ECGroup Node instance type (${var.ecgroup_instance_type}) is not available in the selected Availability Zone (${data.aws_subnet.private_subnet.availability_zone})."
  }
}

# -----------------------------------------------------------------------------
# Pre-flight checks for AMI existence.
# -----------------------------------------------------------------------------

check "ansible_ami_exists" {
  assert {
    condition = !local.deploy_ansible || (
      length(data.aws_ami.ansible_ami_check) > 0 &&
      data.aws_ami.ansible_ami_check[0].id != ""
    )
    error_message = "Validation Error: The specified ansible_ami (ID: ${var.ansible_ami}) was not found in the region ${var.region}."
  }
}

check "client_ami_exists" {
  assert {
    condition = !local.deploy_clients || (
      length(data.aws_ami.client_ami_check) > 0 &&
      data.aws_ami.client_ami_check[0].id != ""
    )
    error_message = "Validation Error: The specified clients_ami (ID: ${var.clients_ami}) was not found in the region ${var.region}."
  }
}

check "ecgroup_node_ami_exists" {
  assert {
    condition = !local.deploy_ecgroup || (
      local.select_ecgroup_ami_for_region != null &&
      length(data.aws_ami.ecgroup_node_ami_check) > 0 &&
      data.aws_ami.ecgroup_node_ami_check[0].id != ""
    )
    error_message = "EC-Group not available for the specified region (${var.region})."
  }
}

check "hammerspace_ami_exists" {
  assert {
    condition = !local.deploy_hammerspace || (
      length(data.aws_ami.hammerspace_ami_check) > 0 &&
      data.aws_ami.hammerspace_ami_check[0].id != ""
    )
    error_message = "Validation Error: The specified hammerspace_ami (ID: ${var.hammerspace_ami}) was not found in the region ${var.region}."
  }
}

check "storage_ami_exists" {
  assert {
    condition = !local.deploy_storage || (
      length(data.aws_ami.storage_ami_check) > 0 &&
      data.aws_ami.storage_ami_check[0].id != ""
    )
    error_message = "Validation Error: The specified storage_ami (ID: ${var.storage_ami}) was not found in the region ${var.region}."
  }
}

# Determine which components to deploy and create a common configuration object

locals {

  all_allowed_cidr_blocks = distinct(concat([data.aws_vpc.validation.cidr_block], var.allowed_source_cidr_blocks))

  common_config = {
    region            = var.region
    availability_zone = data.aws_subnet.private_subnet.availability_zone
    vpc_id            = var.vpc_id
    subnet_id         = var.subnet_id
    key_name          = var.key_name
    tags              = var.tags
    project_name      = var.project_name
    ssh_keys_dir      = var.ssh_keys_dir
    allow_root        = var.allow_root
    placement_group_name = (
      var.placement_group_name != ""
      ? one(aws_placement_group.this[*].name)
      : ""
    )
    allowed_source_cidr_blocks = local.all_allowed_cidr_blocks
  }

  deploy_clients     = contains(var.deploy_components, "all") || contains(var.deploy_components, "clients")
  deploy_storage     = contains(var.deploy_components, "all") || contains(var.deploy_components, "storage")
  deploy_hammerspace = contains(var.deploy_components, "all") || contains(var.deploy_components, "hammerspace")
  deploy_ecgroup     = contains(var.deploy_components, "all") || contains(var.deploy_components, "ecgroup")
  deploy_ansible     = var.ansible_instance_count > 0

  all_ssh_nodes = concat(
    local.deploy_clients ? module.clients[0].client_ansible_info : [],
    local.deploy_storage ? module.storage_servers[0].storage_ansible_info : [],
    local.deploy_ecgroup ? module.ecgroup[0].ecgroup_ansible_info : [],
    local.deploy_hammerspace ? module.hammerspace[0].anvil_ansible_info : [],
    local.deploy_hammerspace ? module.hammerspace[0].dsx_ansible_info : []
  )

  ecgroup_ami_mapping = {
    "eu-west-3"    = "ami-0366b4547202afb15" # Paris
    "us-west-2"    = "ami-029d555d8523da58d" # Oregon
    "us-east-1"    = "ami-00d97e643a6091d85" # Virginia
    "us-east-2"    = "ami-0542e5a5c7395ed56" # Ohio
    "ca-central-1" = "ami-0f8e2a6ca6aeaaf0a" # Canada
  }

  select_ecgroup_ami_for_region = lookup(local.ecgroup_ami_mapping, var.region, "")

  # IAM role... Should we create roles and permissions or use an existing one?

  iam_profile_name = (
    var.iam_profile_name != null
    ? var.iam_profile_name
    : module.iam_core.instance_profile_name
  )
}

# -----------------------------------------------------------------------------
# On-Demand Capacity Reservations
# -----------------------------------------------------------------------------

resource "aws_ec2_capacity_reservation" "anvil" {
  count = local.deploy_hammerspace && var.hammerspace_anvil_count > 0 ? 1 : 0

  instance_type     = var.hammerspace_anvil_instance_type
  instance_platform = "Linux/UNIX"
  availability_zone = data.aws_subnet.private_subnet.availability_zone
  instance_count    = var.hammerspace_anvil_count
  tenancy           = "default"
  end_date_type     = "limited"
  end_date          = timeadd(timestamp(), "10m")
  tags              = merge(var.tags, { Name = "${var.project_name}-Anvil-Reservation" })

  timeouts {
    create = var.capacity_reservation_create_timeout
  }
}

resource "aws_ec2_capacity_reservation" "dsx" {
  count = local.deploy_hammerspace && var.hammerspace_dsx_count > 0 ? 1 : 0

  instance_type     = var.hammerspace_dsx_instance_type
  instance_platform = "Linux/UNIX"
  availability_zone = data.aws_subnet.private_subnet.availability_zone
  instance_count    = var.hammerspace_dsx_count
  tenancy           = "default"
  end_date_type     = "limited"
  end_date          = timeadd(timestamp(), "10m")
  tags              = merge(var.tags, { Name = "${var.project_name}-DSX-Reservation" })

  timeouts {
    create = var.capacity_reservation_create_timeout
  }
}

resource "aws_ec2_capacity_reservation" "clients" {
  count = local.deploy_clients && var.clients_instance_count > 0 ? 1 : 0

  instance_type     = var.clients_instance_type
  instance_platform = "Linux/UNIX"
  availability_zone = data.aws_subnet.private_subnet.availability_zone
  instance_count    = var.clients_instance_count
  tenancy           = "default"
  end_date_type     = "limited"
  end_date          = timeadd(timestamp(), "10m")
  tags              = merge(var.tags, { Name = "${var.project_name}-Clients-Reservation" })

  timeouts {
    create = var.capacity_reservation_create_timeout
  }
}

resource "aws_ec2_capacity_reservation" "storage" {
  count = local.deploy_storage && var.storage_instance_count > 0 ? 1 : 0

  instance_type     = var.storage_instance_type
  instance_platform = "Linux/UNIX"
  availability_zone = data.aws_subnet.private_subnet.availability_zone
  instance_count    = var.storage_instance_count
  tenancy           = "default"
  end_date_type     = "limited"
  end_date          = timeadd(timestamp(), "10m")
  tags              = merge(var.tags, { Name = "${var.project_name}-Storage-Reservation" })

  timeouts {
    create = var.capacity_reservation_create_timeout
  }
}

# ECGroup

resource "aws_ec2_capacity_reservation" "ecgroup_node" {
  count = local.deploy_ecgroup && var.ecgroup_node_count > 3 ? 1 : 0

  instance_type     = var.ecgroup_instance_type
  instance_platform = "Linux/UNIX"
  availability_zone = data.aws_subnet.private_subnet.availability_zone
  instance_count    = var.ecgroup_node_count
  tenancy           = "default"
  end_date_type     = "limited"
  end_date          = timeadd(timestamp(), "10m")
  tags              = merge(var.tags, { Name = "${var.project_name}-ECGroup-Reservation" })

  timeouts {
    create = var.capacity_reservation_create_timeout
  }
}

# Ansible

resource "aws_ec2_capacity_reservation" "ansible" {
  count = local.deploy_ansible && var.ansible_instance_count > 0 ? 1 : 0

  instance_type     = var.ansible_instance_type
  instance_platform = "Linux/UNIX"
  availability_zone = data.aws_subnet.private_subnet.availability_zone
  instance_count    = var.ansible_instance_count
  tenancy           = "default"
  end_date_type     = "limited"
  end_date          = timeadd(timestamp(), "10m")
  tags              = merge(var.tags, { Name = "${var.project_name}-Ansible-Reservation" })

  timeouts {
    create = var.capacity_reservation_create_timeout
  }
}

# -----------------------------------------------------------------------------
# Resource and Module Definitions
# -----------------------------------------------------------------------------

resource "aws_placement_group" "this" {
  count    = var.placement_group_name != "" ? 1 : 0
  name     = var.placement_group_name
  strategy = var.placement_group_strategy
  tags     = var.tags
}

# Build the IAM roles and permissions...
# I put all of the logic into one module that can be referenced
# by all the others. This makes auditing much simpler...

module "iam_core" {
  source = "./modules/iam-core"

  iam_profile_name          = var.iam_profile_name
  common_config             = local.common_config
  role_path                 = var.iam_role_path
  extra_managed_policy_arns = var.iam_additional_policy_arns
}

# Deploy the Ansible module if requested

module "ansible" {
  count  = local.deploy_ansible ? 1 : 0
  source = "./modules/ansible"

  common_config           = local.common_config
  assign_public_ip        = var.assign_public_ip
  public_subnet_id        = var.public_subnet_id
  capacity_reservation_id = local.deploy_ansible && var.ansible_instance_count > 0 ? one(aws_ec2_capacity_reservation.ansible[*].id) : null

  # Pass the path to the key, not the content of the key.

  admin_private_key_path = fileexists("./modules/ansible/id_rsa") ? "./modules/ansible/id_rsa" : ""

  admin_public_key_path = fileexists("./modules/ansible/id_rsa.pub") ? "./modules/ansible/id_rsa.pub" : ""

  instance_count   = var.ansible_instance_count
  ami              = var.ansible_ami
  instance_type    = var.ansible_instance_type
  boot_volume_size = var.ansible_boot_volume_size
  boot_volume_type = var.ansible_boot_volume_type
  target_user      = var.ansible_target_user

  # Pass all nodes to be configured into the module as a JSON string

  target_nodes_json = jsonencode(local.all_ssh_nodes)

  # IAM Roles

  iam_profile_name  = local.iam_profile_name
  iam_profile_group = var.iam_admin_group_name

  # Pass in whether to use SSM and authorized keys

  use_ssm_bootstrap = var.use_ssm_bootstrap
  authorized_keys   = var.authorized_keys

  depends_on = [
    module.iam_core
  ]
}

# Deploy the clients module if requested

module "clients" {
  count  = local.deploy_clients ? 1 : 0
  source = "./modules/clients"

  common_config           = local.common_config
  capacity_reservation_id = local.deploy_clients && var.clients_instance_count > 0 ? one(aws_ec2_capacity_reservation.clients[*].id) : null

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
  tier0            = var.clients_tier0
  tier0_type       = var.clients_tier0_type
  target_user      = var.clients_target_user

  # IAM Roles

  iam_profile_name  = local.iam_profile_name
  iam_profile_group = var.iam_admin_group_name

  depends_on = [
    module.hammerspace
  ]
}

module "storage_servers" {
  count  = local.deploy_storage ? 1 : 0
  source = "./modules/storage_servers"

  common_config           = local.common_config
  capacity_reservation_id = local.deploy_storage && var.storage_instance_count > 0 ? one(aws_ec2_capacity_reservation.storage[*].id) : null

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
  target_user      = var.storage_target_user

  # IAM Roles

  iam_profile_name  = local.iam_profile_name
  iam_profile_group = var.iam_admin_group_name

  depends_on = [
    module.hammerspace
  ]
}

module "hammerspace" {
  count  = local.deploy_hammerspace ? 1 : 0
  source = "git::https://github.com/hammerspace-solutions/terraform-aws-hammerspace.git?ref=iam-changes"

  common_config                 = local.common_config
  assign_public_ip              = var.assign_public_ip
  public_subnet_id              = var.public_subnet_id
  anvil_capacity_reservation_id = local.deploy_hammerspace && var.hammerspace_anvil_count > 0 ? one(aws_ec2_capacity_reservation.anvil[*].id) : null
  dsx_capacity_reservation_id   = local.deploy_hammerspace && var.hammerspace_dsx_count > 0 ? one(aws_ec2_capacity_reservation.dsx[*].id) : null

  ami                        = var.hammerspace_ami
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

  # IAM Roles

  iam_profile_name  = local.iam_profile_name
  iam_profile_group = var.iam_admin_group_name

}

# Deploy the ECGroup module if requested

module "ecgroup" {
  count  = local.deploy_ecgroup ? 1 : 0
  source = "git::https://github.com/hammerspace-solutions/terraform-aws-ecgroups.git?ref=v1.0.4"

  common_config           = local.common_config
  capacity_reservation_id = local.deploy_ecgroup && var.ecgroup_node_count > 3 ? one(aws_ec2_capacity_reservation.ecgroup_node[*].id) : null
  placement_group_name    = var.placement_group_name != "" ? one(aws_placement_group.this[*].name) : ""

  node_count              = var.ecgroup_node_count
  ami                     = local.select_ecgroup_ami_for_region
  instance_type           = var.ecgroup_instance_type
  boot_volume_size        = var.ecgroup_boot_volume_size
  boot_volume_type        = var.ecgroup_boot_volume_type
  metadata_ebs_type       = var.ecgroup_metadata_volume_type
  metadata_ebs_size       = var.ecgroup_metadata_volume_size
  metadata_ebs_throughput = var.ecgroup_metadata_volume_throughput
  metadata_ebs_iops       = var.ecgroup_metadata_volume_iops
  storage_ebs_count       = var.ecgroup_storage_volume_count
  storage_ebs_type        = var.ecgroup_storage_volume_type
  storage_ebs_size        = var.ecgroup_storage_volume_size
  storage_ebs_throughput  = var.ecgroup_storage_volume_throughput
  storage_ebs_iops        = var.ecgroup_storage_volume_iops

  # IAM Roles

  iam_profile_name  = local.iam_profile_name
  iam_profile_group = var.iam_admin_group_name

  depends_on = [
    module.hammerspace
  ]
}

