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
# Availability Zone guardrail
# -----------------------------------------------------------------------------
# Make sure that they don't specify an availability zone if they want to use
# a pre-existing vpc_id
# -----------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"
}

check "az_config_guard" {
  assert {
    condition = (
      # Case 1: Using existing VPC → AZs must NOT be specified
      (local.use_existing_vpc &&
        var.subnet_1_az == null &&
        var.subnet_2_az == null
      )
      ||
      # Case 2: Creating VPC → AZs must be non-empty and valid for this region
      (!local.use_existing_vpc &&
        var.subnet_1_az != null &&
        var.subnet_2_az != null &&
        contains(data.aws_availability_zones.available.names, var.subnet_1_az) &&
        contains(data.aws_availability_zones.available.names, var.subnet_2_az)
      )
    )

    error_message = <<-EOT
      Invalid Availability Zone configuration:

      - When using an existing VPC (vpc_id is set):
        * subnet_1_az and subnet_2_az must be null.
      - When creating a new VPC (vpc_id is null):
        * subnet_1_az and subnet_2_az must be non-empty
        * each must be a valid availability zone in region ${var.region}
    EOT
  }
}

# -----------------------------------------------------------------------------
# Validate that amazon mq credentials are set when amazon mq is enabled
# -----------------------------------------------------------------------------

check "mq_credentials_when_enabled" {
  assert {
    condition = (
      !local.deploy_mq ||
      (
        var.amazonmq_admin_username  != null &&
        var.amazonmq_admin_password  != null &&
        var.amazonmq_site_admin_username      != null &&
        var.amazonmq_site_admin_password      != null &&
        var.amazonmq_site_admin_password_hash != null
      )
    )

    error_message = <<-EOT
      When deploying Amazon MQ (deploy_components includes "mq" or "all"),
      you must set all of the following variables:

        - amazonmq_admin_username
        - amazonmq_admin_password
        - amazonmq_site_admin_username
        - amazonmq_site_admin_password
        - amazonmq_site_admin_password_hash
    EOT
  }
}

# -----------------------------------------------------------------------------
# Network configuration guardrail
# -----------------------------------------------------------------------------
# Rules (enforced via variables.tf validation):
# - Exactly one of vpc_id or vpc_cidr is set
# - For each subnet (private/public 1/2), either *_id or *_cidr is set, not both
# - If vpc_id is set, no subnet CIDRS are allowed.
# - If vpc_id is null, vpc_cidr + all four subnet CIDRs must be set, and all *_id null
# -----------------------------------------------------------------------------

check "network_config_guard" {
  assert {
    condition = (
      # 1) Exactly one of vpc_id / vpc_cidr must be set
      (
        (var.vpc_id != null && var.vpc_cidr == null) ||
        (var.vpc_id == null && var.vpc_cidr != null)
      )
      &&
      # 2) If vpc_id is set, NO subnet CIDRs may be set
      (
        var.vpc_id == null ||
        (
          var.private_subnet_1_cidr == null &&
          var.private_subnet_2_cidr == null &&
          var.public_subnet_1_cidr == null &&
          var.public_subnet_2_cidr == null
        )
      )
      &&
      # 3) For each subnet, you cannot set both ID and CIDR
      !(
        (var.private_subnet_1_id != null && var.private_subnet_1_cidr != null) ||
        (var.private_subnet_2_id != null && var.private_subnet_2_cidr != null) ||
        (var.public_subnet_1_id != null && var.public_subnet_1_cidr != null) ||
        (var.public_subnet_2_id != null && var.public_subnet_2_cidr != null) ||
        # alias conflict: private_subnet_id vs private_subnet_1_id/CIDR
        (var.private_subnet_id != null && var.private_subnet_1_id != null) ||
        (var.private_subnet_id != null && var.private_subnet_1_cidr != null) ||
        (var.public_subnet_id != null && var.public_subnet_1_id != null) ||
        (var.public_subnet_id != null && var.public_subnet_1_cidr != null)
      )
      &&
      # 4) If vpc_id is null (we're creating the VPC):
      #    - vpc_cidr must be set
      #    - All four subnet CIDRs must be set
      #    - No subnet IDs may be set
      (
        var.vpc_id != null ||
        (
          var.vpc_cidr != null &&
          var.private_subnet_1_cidr != null &&
          var.private_subnet_2_cidr != null &&
          var.public_subnet_1_cidr != null &&
          var.public_subnet_2_cidr != null &&
          var.private_subnet_1_id == null &&
          var.private_subnet_2_id == null &&
          var.public_subnet_1_id == null &&
          var.public_subnet_2_id == null
        )
      )
      &&
      # 5) If using an existing VPC (vpc_id set), require at least one private subnet ID
      (
        var.vpc_id == null ||
        (
          # At least one of the private subnet IDs (or alias) must be set
          var.private_subnet_id  != null ||
          var.private_subnet_1_id != null
        )
      )
    )

    error_message = <<-EOT
      Invalid VPC/subnet configuration:

      - You must set exactly ONE of vpc_id or vpc_cidr.
      - If vpc_id is set:
        * vpc_cidr must be null
        * all *_cidr subnet variables must be null
      - For each subnet (private/public, 1/2):
        * you may set either *_id or *_cidr, but not both
      - If vpc_id is null (you are creating the VPC):
        * vpc_cidr must be set
        * all four subnet CIDRs must be set
        * all subnet *_id variables must be null
    EOT
  }
}

# -----------------------------------------------------------------------------
# Network creation / resolution (VPC + subnets)
# -----------------------------------------------------------------------------
# Rules (enforced via variables.tf validation):
# - Exactly one of vpc_id or vpc_cidr is set
# - For each subnet (private/public 1/2), either *_id or *_cidr is set, not both
# - If vpc_id is set, no subnet CIDRS are allowed.
# - If vpc_id is null, vpc_cidr + all four subnet CIDRs must be set, and all *_id null
# -----------------------------------------------------------------------------

locals {
  use_existing_vpc = var.vpc_id != null
}

# Create VPC only if one if not provided

resource "aws_vpc" "main" {
  count      = local.use_existing_vpc ? 0 : 1
  cidr_block = var.vpc_cidr

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = "${var.project_name}-vpc" })
}

# Lookup existing VPC only if vpc_id is provided

data "aws_vpcs" "existing" {
  count = local.use_existing_vpc ? 1 : 0

  filter {
    name = "vpc-id"
    values = [var.vpc_id]
  }
}

# Get the effective vpc id from either an existing or a newly created vpc

data "aws_vpc" "existing" {
  count = local.use_existing_vpc && length(data.aws_vpcs.existing[0].ids) == 1 ? 1 : 0
  id    = data.aws_vpcs.existing[0].ids[0]
}

# Check if the VPC exists and print out an error message if not

check "vpc_exists" {
  assert {
    condition = (
      # If not using existing VPC, we don't care
      !local.use_existing_vpc
      ||
      # If using existing VPC, we must have found exactly one
      length(data.aws_vpcs.existing[0].ids) == 1
    )

    error_message = <<-EOT
      Invalid VPC configuration:

      - You set vpc_id = "${var.vpc_id != null ? var.vpc_id : "<unset>"}", but no matching VPC was found in region "${var.region}".
      - Please double-check:
          * The VPC ID is correct
          * You are using the correct AWS region
    EOT
  }
}

# Get the effective vpc_id and vpc_cidr depending upon whether we use an existing vpc
# or need to create one

locals {
  vpc_id_effective = local.use_existing_vpc ? var.vpc_id : aws_vpc.main[0].id

  # If using existing VPC and it exists, get its CIDR; otherwise fall back to var.vpc_cidr (may be null)
  
  vpc_cidr_effective = (
    local.use_existing_vpc && length(data.aws_vpcs.existing[0].ids) == 1
      ? data.aws_vpc.existing[0].cidr_block
      : var.vpc_cidr
  )

  # Build CIDR list without ever inserting a null
  
  base_allowed_cidrs = local.vpc_cidr_effective != null ? [local.vpc_cidr_effective] : []

  all_allowed_cidr_blocks = distinct(
    concat(
      local.base_allowed_cidrs,
      var.allowed_source_cidr_blocks,
    )
  )
}

# ---------------------------
# Subnets (create or reuse)
# ---------------------------

# Private subnet 1

resource "aws_subnet" "private_1" {
  count = local.use_existing_vpc ? 0 : 1

  vpc_id                  = local.vpc_id_effective
  cidr_block              = var.private_subnet_1_cidr
  availability_zone       = var.subnet_1_az
  map_public_ip_on_launch = false
  tags                    = merge(var.tags, { Name = "${var.project_name}-private-1" })
}

# Private subnet 2

resource "aws_subnet" "private_2" {
  count = local.use_existing_vpc ? 0 : 1

  vpc_id                  = local.vpc_id_effective
  cidr_block              = var.private_subnet_2_cidr
  availability_zone       = var.subnet_2_az
  map_public_ip_on_launch = false
  tags                    = merge(var.tags, { Name = "${var.project_name}-private-2" })
}

# Public subnet 1

resource "aws_subnet" "public_1" {
  count = local.use_existing_vpc ? 0 : 1

  vpc_id                  = local.vpc_id_effective
  cidr_block              = var.public_subnet_1_cidr
  availability_zone       = var.subnet_1_az
  map_public_ip_on_launch = false
  tags                    = merge(var.tags, { Name = "${var.project_name}-public-1" })
}

# Public subnet 2

resource "aws_subnet" "public_2" {
  count = local.use_existing_vpc ? 0 : 1

  vpc_id                  = local.vpc_id_effective
  cidr_block              = var.public_subnet_2_cidr
  availability_zone       = var.subnet_2_az
  map_public_ip_on_launch = false
  tags                    = merge(var.tags, { Name = "${var.project_name}-public-2" })
}

# The effective locals will pick the valid subnet id from either the created or
# already existing subnet

locals {
  # For private subnet 1:
  # - If using existing VPC: take private_subnet_id alias if set, else private_subnet_1_id
  # - If creating VPC: use the created subnet
  private_subnet_1_id_effective = (
    local.use_existing_vpc
    ? (var.private_subnet_id != null ? var.private_subnet_id : var.private_subnet_1_id)
    : aws_subnet.private_1[0].id
  )

  # For private subnet 2:
  # - If using existing VPC: just pass through whatever the user set (can be null)
  # - If creating VPC: use the created subnet
  private_subnet_2_id_effective = (
    local.use_existing_vpc
    ? var.private_subnet_2_id
    : aws_subnet.private_2[0].id
  )

  # For public subnet 1:
  public_subnet_1_id_effective = (
    local.use_existing_vpc
    ? (var.public_subnet_id != null ? var.public_subnet_id : var.public_subnet_1_id)
    : aws_subnet.public_1[0].id
  )

  # For public subnet 2:
  public_subnet_2_id_effective = (
    local.use_existing_vpc
    ? var.public_subnet_2_id
    : aws_subnet.public_2[0].id
  )
}

# First, try to find the "primary" private subnet in a non-fatal way
data "aws_subnets" "private_primary" {
  count = local.use_existing_vpc ? 1 : 0

  filter {
    name   = "subnet-id"
    values = [local.private_subnet_1_id_effective]
  }
}

check "private_primary_subnet_exists" {
  assert {
    condition = (
      # If we're creating the VPC ourselves, the subnet will be created, so skip this.
      !local.use_existing_vpc
      ||
      (
        local.private_subnet_1_id_effective != null &&
        length(data.aws_subnets.private_primary[0].ids) == 1
      )
    )

    error_message = <<-EOT
      Invalid subnet configuration:

      - You set private_subnet_id/private_subnet_1_id = "${local.private_subnet_1_id_effective != null ? local.private_subnet_1_id_effective : "<unset>"}",
        but no matching subnet was found in region "${var.region}".
      - Please double-check:
          * The subnet ID is correct
          * You are using the correct AWS region
          * The subnet belongs to VPC "${var.vpc_id != null ? var.vpc_id : "<unset>"}"
    EOT
  }
}

# We pick private_subnet_1 as the "primary" AZ for capacity reservations, etc.

data "aws_subnet" "private_primary" {
  count = local.use_existing_vpc ? length(data.aws_subnets.private_primary[0].ids) : 0
  id = local.private_subnet_1_id_effective
}

# Get the primary availability zone

locals {
  primary_az = (
    local.use_existing_vpc
    ? (length(data.aws_subnet.private_primary) > 0
      ? data.aws_subnet.private_primary[0].availability_zone
      : null
      )
    : var.subnet_1_az
  )
}


# -----------------------------------------------------------------------------
# (Optional) Network infrastructure when we CREATE the VPC
#   - If vpc_id is provided, we assume the existing network already has IGW/NAT/etc.
# -----------------------------------------------------------------------------

# Internet Gateway

resource "aws_internet_gateway" "this" {
  count  = local.use_existing_vpc ? 0 : 1
  vpc_id = local.vpc_id_effective

  tags = merge(var.tags, { Name = "${var.project_name}-igw" })
}

# NAT Gateway (in public subnet 1)

resource "aws_eip" "nat" {
  count  = local.use_existing_vpc ? 0 : 1
  domain = "vpc"

  tags = merge(var.tags, { Name = "${var.project_name}-nat-eip" })
}

resource "aws_nat_gateway" "this" {
  count         = local.use_existing_vpc ? 0 : 1
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public_1[0].id

  tags = merge(var.tags, { Name = "${var.project_name}-nat" })
}

# Public route table (IGW)

resource "aws_route_table" "public" {
  count  = local.use_existing_vpc ? 0 : 1
  vpc_id = local.vpc_id_effective

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this[0].id
  }

  tags = merge(var.tags, { Name = "${var.project_name}-public-rt" })
}

resource "aws_route_table_association" "public_1" {
  count          = local.use_existing_vpc ? 0 : 1
  subnet_id      = aws_subnet.public_1[0].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_route_table_association" "public_2" {
  count          = local.use_existing_vpc ? 0 : 1
  subnet_id      = aws_subnet.public_2[0].id
  route_table_id = aws_route_table.public[0].id
}

# Private route table (NAT)

resource "aws_route_table" "private" {
  count  = local.use_existing_vpc ? 0 : 1
  vpc_id = local.vpc_id_effective

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[0].id
  }

  tags = merge(var.tags, { Name = "${var.project_name}-private-rt" })
}

resource "aws_route_table_association" "private_1" {
  count          = local.use_existing_vpc ? 0 : 1
  subnet_id      = aws_subnet.private_1[0].id
  route_table_id = aws_route_table.private[0].id
}

resource "aws_route_table_association" "private_2" {
  count          = local.use_existing_vpc ? 0 : 1
  subnet_id      = aws_subnet.private_2[0].id
  route_table_id = aws_route_table.private[0].id
}

# -----------------------------------------------------------------------------
# Pre-flight checks for AMI existence and instance types
# (Networking checks that referenced var.vpc_id / var.subnet_id are removed)
# -----------------------------------------------------------------------------

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
# Pre-flight checks for instance type existence.
# -----------------------------------------------------------------------------

data "aws_ec2_instance_type_offerings" "anvil_check" {
  # Only query AWS when we actually know the primary AZ
  count = local.primary_az != null ? 1 : 0

  provider = aws

  filter {
    name   = "instance-type"
    values = [var.hammerspace_anvil_instance_type]
  }

  filter {
    name   = "location"
    values = [local.primary_az]
  }

  location_type = "availability-zone"
}

check "anvil_instance_type_is_available" {
  assert {
    condition = (
      # If we don't know the AZ, skip this check (network checks will already fail)
      local.primary_az == null
      ||
      # Otherwise, ensure the instance type is available in that AZ
      sum([
        for d in data.aws_ec2_instance_type_offerings.anvil_check :
        length(d.instance_types)
      ]) > 0
    )

    error_message = (
      local.primary_az != null
      ? "The specified Anvil instance type (${var.hammerspace_anvil_instance_type}) is not available in the selected Availability Zone (${local.primary_az})."
      : "Unable to determine primary Availability Zone. Please verify your VPC and subnet configuration before checking instance type availability."
    )
  }
}

data "aws_ec2_instance_type_offerings" "dsx_check" {
  # Only query AWS when we actually know the primary AZ
  count = local.primary_az != null ? 1 : 0

  provider = aws

  filter {
    name   = "instance-type"
    values = [var.hammerspace_dsx_instance_type]
  }

  filter {
    name   = "location"
    values = [local.primary_az]
  }

  location_type = "availability-zone"
}

check "dsx_instance_type_is_available" {
  assert {
    condition = (
      # If we don't know the AZ, skip this check (network checks will already fail)
      local.primary_az == null
      ||
      # Otherwise, ensure the instance type is available in that AZ
      sum([
        for d in data.aws_ec2_instance_type_offerings.dsx_check :
        length(d.instance_types)
      ]) > 0
    )

    error_message = (
      local.primary_az != null
      ? "The specified DSX instance type (${var.hammerspace_dsx_instance_type}) is not available in the selected Availability Zone (${local.primary_az})."
      : "Unable to determine primary Availability Zone. Please verify your VPC and subnet configuration before checking instance type availability."
    )
  }
}

data "aws_ec2_instance_type_offerings" "client_check" {
  # Only query AWS when we actually know the primary AZ
  count = local.primary_az != null ? 1 : 0

  provider = aws

  filter {
    name   = "instance-type"
    values = [var.clients_instance_type]
  }

  filter {
    name   = "location"
    values = [local.primary_az]
  }

  location_type = "availability-zone"
}

check "client_instance_type_is_available" {
  assert {
    condition = (
      # If we don't know the AZ, skip this check (network checks will already fail)
      local.primary_az == null
      ||
      # Otherwise, ensure the instance type is available in that AZ
      sum([
        for d in data.aws_ec2_instance_type_offerings.client_check :
        length(d.instance_types)
      ]) > 0
    )

    error_message = (
      local.primary_az != null
      ? "The specified Client instance type (${var.clients_instance_type}) is not available in the selected Availability Zone (${local.primary_az})."
      : "Unable to determine primary Availability Zone. Please verify your VPC and subnet configuration before checking instance type availability."
    )
  }
}

data "aws_ec2_instance_type_offerings" "storage_check" {
  # Only query AWS when we actually know the primary AZ
  count = local.primary_az != null ? 1 : 0

  provider = aws

  filter {
    name   = "instance-type"
    values = [var.storage_instance_type]
  }

  filter {
    name   = "location"
    values = [local.primary_az]
  }

  location_type = "availability-zone"
}

check "storage_instance_type_is_available" {
  assert {
    condition = (
      # If we don't know the AZ, skip this check (network checks will already fail)
      local.primary_az == null
      ||
      # Otherwise, ensure the instance type is available in that AZ
      sum([
        for d in data.aws_ec2_instance_type_offerings.storage_check :
        length(d.instance_types)
      ]) > 0
    )

    error_message = (
      local.primary_az != null
      ? "The specified Storage instance type (${var.storage_instance_type}) is not available in the selected Availability Zone (${local.primary_az})."
      : "Unable to determine primary Availability Zone. Please verify your VPC and subnet configuration before checking instance type availability."
    )
  }
}

data "aws_ec2_instance_type_offerings" "ecgroup_check" {
  # Only query AWS when we actually know the primary AZ
  count = local.primary_az != null ? 1 : 0

  provider = aws

  filter {
    name   = "instance-type"
    values = [var.ecgroup_instance_type]
  }

  filter {
    name   = "location"
    values = [local.primary_az]
  }

  location_type = "availability-zone"
}

check "ecgroup_instance_type_is_available" {
  assert {
    condition = (
      # If we don't know the AZ, skip this check (network checks will already fail)
      local.primary_az == null
      ||
      # Otherwise, ensure the instance type is available in that AZ
      sum([
        for d in data.aws_ec2_instance_type_offerings.ecgroup_check :
        length(d.instance_types)
      ]) > 0
    )

    error_message = (
      local.primary_az != null
      ? "The specified ECGroup instance type (${var.ecgroup_instance_type}) is not available in the selected Availability Zone (${local.primary_az})."
      : "Unable to determine primary Availability Zone. Please verify your VPC and subnet configuration before checking instance type availability."
    )
  }
}

# Determine which components to deploy and create a common configuration object

locals {

  common_config = {
    region            = var.region
    availability_zone = local.primary_az
    vpc_id            = local.vpc_id_effective
    subnet_id         = local.private_subnet_1_id_effective
    key_name          = var.key_name
    tags              = var.tags
    project_name      = var.project_name
    ssh_keys_dir      = var.ssh_keys_dir
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
  deploy_mq	     = contains(var.deploy_components, "all") || contains(var.deploy_components, "mq")
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
  count = local.deploy_hammerspace && var.hammerspace_anvil_count > 0 && local.primary_az != null ? 1 : 0

  instance_type     = var.hammerspace_anvil_instance_type
  instance_platform = "Linux/UNIX"
  availability_zone = local.primary_az
  instance_count    = var.hammerspace_anvil_count
  tenancy           = "default"
  end_date_type     = "limited"
  end_date          = timeadd(timestamp(), var.capacity_reservation_expiration)
  tags              = merge(var.tags, { Name = "${var.project_name}-Anvil-Reservation" })

  timeouts {
    create = var.capacity_reservation_create_timeout
  }
}

resource "aws_ec2_capacity_reservation" "dsx" {
  count = local.deploy_hammerspace && var.hammerspace_dsx_count > 0 && local.primary_az != null ? 1 : 0

  instance_type     = var.hammerspace_dsx_instance_type
  instance_platform = "Linux/UNIX"
  availability_zone = local.primary_az
  instance_count    = var.hammerspace_dsx_count
  tenancy           = "default"
  end_date_type     = "limited"
  end_date          = timeadd(timestamp(), var.capacity_reservation_expiration)
  tags              = merge(var.tags, { Name = "${var.project_name}-DSX-Reservation" })

  timeouts {
    create = var.capacity_reservation_create_timeout
  }
}

resource "aws_ec2_capacity_reservation" "clients" {
  count = local.deploy_clients && var.clients_instance_count > 0 && local.primary_az != null ? 1 : 0

  instance_type     = var.clients_instance_type
  instance_platform = "Linux/UNIX"
  availability_zone = local.primary_az
  instance_count    = var.clients_instance_count
  tenancy           = "default"
  end_date_type     = "limited"
  end_date          = timeadd(timestamp(), var.capacity_reservation_expiration)
  tags              = merge(var.tags, { Name = "${var.project_name}-Clients-Reservation" })

  timeouts {
    create = var.capacity_reservation_create_timeout
  }
}

resource "aws_ec2_capacity_reservation" "storage" {
  count = local.deploy_storage && var.storage_instance_count > 0 && local.primary_az != null ? 1 : 0

  instance_type     = var.storage_instance_type
  instance_platform = "Linux/UNIX"
  availability_zone = local.primary_az
  instance_count    = var.storage_instance_count
  tenancy           = "default"
  end_date_type     = "limited"
  end_date          = timeadd(timestamp(), var.capacity_reservation_expiration)
  tags              = merge(var.tags, { Name = "${var.project_name}-Storage-Reservation" })

  timeouts {
    create = var.capacity_reservation_create_timeout
  }
}

# ECGroup

resource "aws_ec2_capacity_reservation" "ecgroup_node" {
  count = local.deploy_ecgroup && var.ecgroup_node_count > 3 && local.primary_az != null ? 1 : 0

  instance_type     = var.ecgroup_instance_type
  instance_platform = "Linux/UNIX"
  availability_zone = local.primary_az
  instance_count    = var.ecgroup_node_count
  tenancy           = "default"
  end_date_type     = "limited"
  end_date          = timeadd(timestamp(), var.capacity_reservation_expiration)
  tags              = merge(var.tags, { Name = "${var.project_name}-ECGroup-Reservation" })

  timeouts {
    create = var.capacity_reservation_create_timeout
  }
}

# Ansible

resource "aws_ec2_capacity_reservation" "ansible" {
  count = local.deploy_ansible && var.ansible_instance_count > 0 && local.primary_az != null ? 1 : 0

  instance_type     = var.ansible_instance_type
  instance_platform = "Linux/UNIX"
  availability_zone = local.primary_az
  instance_count    = var.ansible_instance_count
  tenancy           = "default"
  end_date_type     = "limited"
  end_date          = timeadd(timestamp(), var.capacity_reservation_expiration)
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

  iam_profile_name               = var.iam_profile_name
  common_config                  = local.common_config
  role_path                      = var.iam_role_path
  extra_managed_policy_arns      = var.iam_additional_policy_arns
  ansible_private_key_secret_arn = var.ansible_private_key_secret_arn

}

# Deploy the Ansible module if requested

module "ansible" {
  count  = local.deploy_ansible ? 1 : 0
  source = "./modules/ansible"

  common_config           = local.common_config
  assign_public_ip        = var.assign_public_ip
  public_subnet_id        = local.public_subnet_1_id_effective
  capacity_reservation_id = local.deploy_ansible && var.ansible_instance_count > 0 ? one(aws_ec2_capacity_reservation.ansible[*].id) : null

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

  # Use public / private key for ansible communication

  ansible_ssh_public_key         = var.ansible_ssh_public_key
  ansible_private_key_secret_arn = var.ansible_private_key_secret_arn

  # Security for ssh control

  ansible_controller_cidr = var.ansible_controller_cidr

  # Pass the volume group and share names so that they can be automatically
  # created in an Anvil

  config_ansible = var.config_ansible

  # Pass the ecgroup_metadata information if ECGroups were deployed

  ecgroup_metadata_array = local.deploy_ecgroup ? one(module.ecgroup[*].metadata_array) : ""
  ecgroup_storage_array  = local.deploy_ecgroup ? one(module.ecgroup[*].storage_array) : ""

  depends_on = [
    module.iam_core
  ]
}

# Deploy the Amazon MQ module is desired

module "amazon_mq" {
  count  = local.deploy_mq ? 1 : 0
  source = "git::https://github.com/hammerspace-solutions/terraform-aws-amazon-mq.git?ref=v1.0.0"

  project_name	   = var.project_name
  region	   = var.region
  vpc_id	   = local.vpc_id_effective
  subnet_1_id	   = local.private_subnet_1_id_effective
  subnet_2_id	   = local.private_subnet_2_id_effective
  instance_type    = var.amazonmq_instance_type
  engine_version   = var.amazonmq_engine_version
  admin_username   = var.amazonmq_admin_username
  admin_password   = var.amazonmq_admin_password
  site_username	   = var.amazonmq_site_admin_username
  site_password	   = var.amazonmq_site_admin_password
  site_password_hash = var.amazonmq_site_admin_password_hash
  hosted_zone_name = var.hosted_zone_name
  tags		   = var.tags
  
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

  # Key and security group(s) needed for ansible configuration

  ansible_key_name = module.ansible[0].ansible_key_name
  ansible_sg_id    = module.ansible[0].allow_ssh_from_ansible_sg_id

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

  # Key and security group(s) needed for ansible configuration

  ansible_key_name = module.ansible[0].ansible_key_name
  ansible_sg_id    = module.ansible[0].allow_ssh_from_ansible_sg_id

  depends_on = [
    module.hammerspace
  ]
}

module "hammerspace" {
  count  = local.deploy_hammerspace ? 1 : 0
  source = "git::https://github.com/hammerspace-solutions/terraform-aws-hammerspace.git?ref=v1.0.6"

  common_config                 = local.common_config
  assign_public_ip              = var.assign_public_ip
  public_subnet_id              = local.public_subnet_1_id_effective
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
  source = "git::https://github.com/hammerspace-solutions/terraform-aws-ecgroups.git?ref=v1.0.9"

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

  # Use private key for ansible communication

  ansible_private_key_secret_arn = var.ansible_private_key_secret_arn

  # IAM Roles

  iam_profile_name  = local.iam_profile_name
  iam_profile_group = var.iam_admin_group_name

  # Key and security group(s) needed for ansible configuration

  ansible_key_name = module.ansible[0].ansible_key_name
  ansible_sg_id    = module.ansible[0].allow_ssh_from_ansible_sg_id

  depends_on = [
    module.hammerspace
  ]
}
