# Terraform-AWS

Terraform infrastructure-as-code for deploying Hammerspace Global Data Environment on Amazon Web Services (AWS).

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Component Selection](#component-selection)
- [Deployment Scenarios](#deployment-scenarios)
  - [Scenario 1: Standalone Anvil Only](#scenario-1-standalone-anvil-only)
  - [Scenario 2: Anvil + DSX Nodes](#scenario-2-anvil--dsx-nodes)
  - [Scenario 3: High-Availability (HA) Deployment with 2 Anvils](#scenario-3-high-availability-ha-deployment-with-2-anvils)
  - [Scenario 4: Hammerspace + ECGroup](#scenario-4-hammerspace--ecgroup)
  - [Scenario 5: Hammerspace + Storage Servers](#scenario-5-hammerspace--storage-servers)
  - [Scenario 6: Full Production Stack](#scenario-6-full-production-stack)
- [Networking Options](#networking-options)
- [Instance Types](#instance-types)
- [Placement Control](#placement-control)
- [Volume Groups & Shares](#volume-groups--shares)
- [AWS Managed Services](#aws-managed-services)
- [Tier-0 Local NVMe](#tier-0-local-nvme)
- [Outputs](#outputs)
- [Feature Matrix](#feature-matrix)
- [Pre-flight Validation](#pre-flight-validation)
- [Troubleshooting](#troubleshooting)
- [Clean Up](#clean-up)
- [File Structure](#file-structure)
- [License](#license)

---

## Overview

This Terraform project provides a modular, production-ready deployment of Hammerspace components on AWS, including:

- **Hammerspace Anvil** - Metadata controller (standalone or HA)
- **Hammerspace DSX** - Data services nodes
- **ECGroup (RozoFS)** - Erasure-coded distributed storage
- **Storage Servers** - Generic storage nodes with RAID support
- **Ansible Controller** - Automated configuration management
- **Client Instances** - NFS/SMB client nodes
- **Amazon MQ** - RabbitMQ message broker
- **Aurora Database** - PostgreSQL/MySQL compatible database

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                      AWS Region                                         │
│  ┌───────────────────────────────────────────────────────────────────────────────────┐  │
│  │                                       VPC                                         │  │
│  │  ┌─────────────────────────────────────────────────────────────────────────────┐  │  │
│  │  │                              Private Subnet                                 │  │  │
│  │  │                                                                             │  │  │
│  │  │  ┌──────────────────────────────────────────────────────────────────────┐   │  │  │
│  │  │  │                      HAMMERSPACE CORE                                │   │  │  │
│  │  │  │  ┌─────────────────────────────────────────────────────────────────┐ │   │  │  │
│  │  │  │  │                        Anvil                                    │ │   │  │  │
│  │  │  │  │                 (Metadata Controller)                           │ │   │  │  │
│  │  │  │  │                                                                 │ │   │  │  │
│  │  │  │  │         Standalone (1) or HA Mode (2 nodes)                     │ │   │  │  │
│  │  │  │  └────────────────────────────┬────────────────────────────────────┘ │   │  │  │
│  │  │  │                               │                                      │   │  │  │
│  │  │  │             ┌─────────────────┴─────────────────┐                    │   │  │  │
│  │  │  │             ▼                                   ▼                    │   │  │  │
│  │  │  │    ┌─────────────────┐             ┌─────────────────┐               │   │  │  │
│  │  │  │    │   DSX Node 0    │     ...     │   DSX Node N    │               │   │  │  │
│  │  │  │    │   (Optional)    │             │   (Optional)    │               │   │  │  │
│  │  │  │    │  Data Services  │             │  Data Services  │               │   │  │  │
│  │  │  │    └────────┬────────┘             └────────┬────────┘               │   │  │  │
│  │  │  │             │                               │                        │   │  │  │
│  │  │  │             ▼                               ▼                        │   │  │  │
│  │  │  │    ┌────────────────────────────────────────────────────────────┐    │   │  │  │
│  │  │  │    │                    EBS Volumes (AWS)                       │    │   │  │  │
│  │  │  │    └────────────────────────────────────────────────────────────┘    │   │  │  │
│  │  │  └──────────────────────────────────────────────────────────────────────┘   │  │  │
│  │  │                                                                             │  │  │
│  │  │  ┌──────────────────────────────┐    ┌──────────────────────────────────┐   │  │  │
│  │  │  │     STORAGE BACKENDS         │    │      AUTOMATION & CLIENTS        │   │  │  │
│  │  │  │         (Optional)           │    │          (Optional)              │   │  │  │
│  │  │  │                              │    │                                  │   │  │  │
│  │  │  │  ┌────────────────────────┐  │    │  ┌────────────────────────────┐  │   │  │  │
│  │  │  │  │    ECGroup (RozoFS)    │  │    │  │    Ansible Controller      │  │   │  │  │
│  │  │  │  │                        │  │    │  │                            │  │   │  │  │
│  │  │  │  │  ┌──────┐ ┌──────┐     │  │    │  │  Automated Configuration   │  │   │  │  │
│  │  │  │  │  │Node 1│ │Node 2│ ... │  │    │  │  - Add storage nodes       │  │   │  │  │
│  │  │  │  │  └──────┘ └──────┘     │  │    │  │  - Create volume groups    │  │   │  │  │
│  │  │  │  │                        │  │    │  │  - Configure shares        │  │   │  │  │
│  │  │  │  │  Erasure-coded storage │  │    │  └────────────────────────────┘  │   │  │  │
│  │  │  │  └────────────────────────┘  │    │                                  │   │  │  │
│  │  │  │                              │    │  ┌────────────────────────────┐  │   │  │  │
│  │  │  │  ┌────────────────────────┐  │    │  │     Client Instances       │  │   │  │  │
│  │  │  │  │    Storage Servers     │  │    │  │                            │  │   │  │  │
│  │  │  │  │                        │  │    │  │  NFS/SMB mount points      │  │   │  │  │
│  │  │  │  │  Generic block storage │  │    │  │  Tier-0 NVMe support       │  │   │  │  │
│  │  │  │  │  with RAID support     │  │    │  └────────────────────────────┘  │   │  │  │
│  │  │  │  └────────────────────────┘  │    │                                  │   │  │  │
│  │  │  └──────────────────────────────┘    └──────────────────────────────────┘   │  │  │
│  │  │                                                                             │  │  │
│  │  │  ┌──────────────────────────────────────────────────────────────────────┐   │  │  │
│  │  │  │                    AWS MANAGED SERVICES (Optional)                   │   │  │  │
│  │  │  │  ┌────────────────────────┐    ┌────────────────────────┐            │   │  │  │
│  │  │  │  │     Amazon MQ          │    │     Aurora Database    │            │   │  │  │
│  │  │  │  │    (RabbitMQ)          │    │  (PostgreSQL/MySQL)    │            │   │  │  │
│  │  │  │  └────────────────────────┘    └────────────────────────┘            │   │  │  │
│  │  │  └──────────────────────────────────────────────────────────────────────┘   │  │  │
│  │  └─────────────────────────────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                              COMPONENT SUMMARY                                          │
├─────────────────────┬───────────┬───────────────────────────────────────────────────────┤
│ Component           │ Required  │ Description                                           │
├─────────────────────┼───────────┼───────────────────────────────────────────────────────┤
│ Anvil               │ Yes       │ Metadata controller (standalone or HA)                │
│ DSX Nodes           │ Optional  │ Hammerspace data services with EBS volumes            │
│ ECGroup (RozoFS)    │ Optional  │ Erasure-coded distributed storage backend             │
│ Storage Servers     │ Optional  │ Generic storage nodes with RAID support               │
│ Ansible Controller  │ Optional  │ Automated configuration and integration               │
│ Client Instances    │ Optional  │ NFS/SMB clients with Tier-0 NVMe support              │
│ Amazon MQ           │ Optional  │ RabbitMQ message broker                               │
│ Aurora Database     │ Optional  │ PostgreSQL/MySQL compatible database                  │
└─────────────────────┴───────────┴───────────────────────────────────────────────────────┘
```

## Prerequisites

### Required

- **[Terraform](https://developer.hashicorp.com/terraform/downloads)** >= 1.0.0
- **[AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)** configured with valid credentials
- **[AWS Account](https://aws.amazon.com/premiumsupport/knowledge-center/create-and-activate-aws-account/)** with appropriate permissions
- **[Hammerspace AMI](https://aws.amazon.com/marketplace/pp/prodview-3foicv5pgwl46)** subscription (AWS Marketplace)

### AWS Credentials

Create or update `~/.aws/credentials`:

```ini
[default]
aws_access_key_id = YOUR_ACCESS_KEY
aws_secret_access_key = YOUR_SECRET_KEY
```

Create or update `~/.aws/config`:

```ini
[default]
region = us-west-2
```

### Ansible SSH Keys (Required for Ansible Controller)

Generate and store SSH keys for Ansible:

```bash
# Generate key pair
ssh-keygen -t ed25519 -f ansible_controller_key -C "Ansible Controller Key"

# Store private key in AWS Secrets Manager
aws secretsmanager create-secret \
  --name ansible-controller-private-key \
  --secret-string file://ansible_controller_key \
  --region us-west-2
```

Note the ARN for `ansible_private_key_secret_arn` in your tfvars.

## Quick Start

### 1. Clone and Configure

```bash
# Copy example configuration
cp example_terraform.tfvars.rename terraform.tfvars

# Edit with your values
vim terraform.tfvars
```

### 2. Minimum Required Variables

```hcl
# Project
project_name = "hammerspace-lab"
region       = "us-west-2"

# Networking (create new VPC)
vpc_cidr             = "10.0.0.0/16"
private_subnet_1_cidr = "10.0.1.0/24"
private_subnet_2_cidr = "10.0.2.0/24"
public_subnet_1_cidr  = "10.0.101.0/24"
public_subnet_2_cidr  = "10.0.102.0/24"
subnet_1_az          = "us-west-2a"
subnet_2_az          = "us-west-2b"

# SSH
key_name = "your-ec2-keypair"

# AMIs
hammerspace_ami = "ami-xxxxx"  # Hammerspace marketplace AMI
ansible_ami     = "ami-xxxxx"  # Ubuntu AMI

# What to deploy
deploy_components       = ["hammerspace"]
hammerspace_anvil_count = 1
hammerspace_dsx_count   = 0
ansible_instance_count  = 1
```

### 3. Deploy

```bash
# Initialize Terraform
terraform init

# Review the plan (pre-flight validation runs here)
terraform plan

# Apply the configuration
terraform apply
```

> **Note**: Pre-flight validation checks run during `terraform plan` and will catch configuration errors before any resources are created.

### 4. Access Hammerspace

After deployment:

```
https://<anvil-private-ip>:443
Username: admin
Password: (set via Ansible or default)
```

## Component Selection

Use `deploy_components` to select which components to deploy:

```hcl
# Deploy only Hammerspace (Anvil + optional DSX)
deploy_components = ["hammerspace"]

# Deploy Hammerspace with ECGroup storage backend
deploy_components = ["hammerspace", "ecgroup"]

# Deploy with AWS managed services
deploy_components = ["hammerspace", "mq", "aurora"]

# Deploy everything
deploy_components = ["all"]
```

### Available Components

| Component | Description |
|-----------|-------------|
| `hammerspace` | Anvil metadata server + DSX data services |
| `ecgroup` | RozoFS erasure-coded storage cluster (4-16 nodes) |
| `storage` | Generic storage server instances with RAID |
| `clients` | NFS/SMB client instances with Tier-0 support |
| `mq` | Amazon MQ (RabbitMQ) message broker |
| `aurora` | Aurora PostgreSQL/MySQL database |
| `all` | Deploy all components |

## Deployment Scenarios

### Scenario 1: Standalone Anvil Only

Deploy just the metadata server:

```hcl
deploy_components       = ["hammerspace"]
hammerspace_anvil_count = 1
hammerspace_dsx_count   = 0
ansible_instance_count  = 1
```

### Scenario 2: Anvil + DSX Nodes

Full Hammerspace deployment with data services:

```hcl
deploy_components       = ["hammerspace"]
hammerspace_anvil_count = 1
hammerspace_dsx_count   = 2
hammerspace_dsx_add_vols = true

# DSX storage configuration
hammerspace_dsx_ebs_count = 4
hammerspace_dsx_ebs_size  = 500  # GB per volume
```

### Scenario 3: High-Availability (HA) Deployment with 2 Anvils

High-availability deployment with 2 Anvils:

```hcl
deploy_components       = ["hammerspace"]
hammerspace_anvil_count = 2
hammerspace_dsx_count   = 4
ansible_instance_count  = 1
```

### Scenario 4: Hammerspace + ECGroup

Use erasure-coded RozoFS storage:

```hcl
deploy_components       = ["hammerspace", "ecgroup"]
hammerspace_anvil_count = 1
hammerspace_dsx_count   = 0
ecgroup_node_count      = 4
ansible_instance_count  = 1

config_ansible = {
  allow_root           = false
  ecgroup_volume_group = "ecg-vg"
  ecgroup_share_name   = "ecg-share"
  volume_groups        = {}
}
```

### Scenario 5: Hammerspace + Storage Servers

Use generic storage with RAID:

```hcl
deploy_components      = ["hammerspace", "storage"]
hammerspace_anvil_count = 1
hammerspace_dsx_count   = 0
storage_instance_count  = 2
storage_ebs_count       = 4
storage_raid_level      = "raid-5"
ansible_instance_count  = 1

config_ansible = {
  allow_root           = false
  ecgroup_volume_group = null
  ecgroup_share_name   = null
  volume_groups = {
    "storage-vg" = {
      volumes    = ["1", "2"]
      add_groups = []
      share      = "storage-data"
    }
  }
}
```

### Scenario 6: Full Production Stack

Deploy all components:

```hcl
deploy_components       = ["hammerspace", "ecgroup", "storage", "clients", "mq", "aurora"]
hammerspace_anvil_count = 2
hammerspace_dsx_count   = 4
ecgroup_node_count      = 4
storage_instance_count  = 2
clients_instance_count  = 4
ansible_instance_count  = 1

# Placement group for performance
placement_group_name     = "hammerspace-cluster"
placement_group_strategy = "cluster"
```

## Networking Options

### Create New VPC

```hcl
vpc_cidr              = "10.0.0.0/16"
private_subnet_1_cidr = "10.0.1.0/24"
private_subnet_2_cidr = "10.0.2.0/24"
public_subnet_1_cidr  = "10.0.101.0/24"
public_subnet_2_cidr  = "10.0.102.0/24"
subnet_1_az           = "us-west-2a"
subnet_2_az           = "us-west-2b"
```

### Use Existing VPC/Subnets

```hcl
vpc_id              = "vpc-0123456789abcdef0"
private_subnet_id   = "subnet-0123456789abcdef0"
public_subnet_id    = "subnet-fedcba9876543210f"
private_subnet_2_id = "subnet-0987654321fedcba0"  # For Aurora/MQ multi-AZ
```

### Public vs Private Deployment

```hcl
# Public IPs for Ansible (default: false)
assign_public_ip = true

# Restrict ingress to specific CIDRs
allowed_source_cidr_blocks = ["10.0.0.0/8", "192.168.1.0/24"]
```

## Instance Types

### Default Instance Types

| Component | Default Type | Description |
|-----------|-------------|-------------|
| Anvil | `m5zn.12xlarge` | High-frequency compute |
| DSX | `m5.xlarge` | Balanced compute |
| ECGroup | `m6i.16xlarge` | Memory-optimized |
| Storage | `m5.xlarge` | General purpose |
| Clients | `m5.xlarge` | General purpose |
| Ansible | `m5n.8xlarge` | Network-optimized |

### Custom Instance Types

```hcl
hammerspace_anvil_instance_type = "m5zn.12xlarge"
hammerspace_dsx_instance_type   = "m5.2xlarge"
ecgroup_instance_type           = "m6i.16xlarge"
storage_instance_type           = "m5.xlarge"
clients_instance_type           = "m5.xlarge"
```

## Placement Control

### Availability Zones

```hcl
subnet_1_az = "us-west-2a"
subnet_2_az = "us-west-2b"
```

### Placement Groups

```hcl
placement_group_name     = "hammerspace-cluster"
placement_group_strategy = "cluster"  # cluster, spread, or partition
```

### Capacity Reservations

```hcl
capacity_reservation_create_timeout = "5m"
capacity_reservation_expiration     = "5m"
```

> **Warning**: Capacity reservations are billed as soon as created, even without running instances.

## Volume Groups & Shares

Configure storage organization in Hammerspace via `config_ansible`:

```hcl
config_ansible = {
  allow_root           = false
  ecgroup_volume_group = "ecg-vg"
  ecgroup_share_name   = "ecg-share"
  volume_groups = {
    "storage-vg" = {
      volumes    = ["1", "2"]        # Storage server indexes
      add_groups = ["group1"]        # Optional AD groups
      share      = "storage-data"    # Share name
    }
  }
}
```

## AWS Managed Services

### Amazon MQ (RabbitMQ)

```hcl
deploy_components = ["hammerspace", "mq"]

amazonmq_instance_type    = "mq.m5.large"
amazonmq_engine_version   = "3.13"
amazonmq_admin_username   = "admin"
amazonmq_admin_password   = "SecurePassword123!"
```

### Aurora Database

```hcl
deploy_components = ["hammerspace", "aurora"]

aurora_engine         = "aurora-postgresql"
aurora_engine_version = "15.3"
aurora_instance_class = "db.r6g.large"
aurora_instance_count = 2
aurora_db_name        = "hammerspace"
aurora_master_username = "admin"
aurora_master_password = "SecurePassword123!"
```

## Tier-0 Local NVMe

[Tier-0](https://hammerspace.com/tier-0/) provides high-performance local storage on client instances for caching frequently accessed data:

```hcl
clients_tier0      = "raid-0"  # raid-0, raid-5, or raid-6
clients_tier0_type = "raid-0"
```

| RAID Level | Required NVMe Disks |
|------------|---------------------|
| raid-0 | 2 |
| raid-5 | 3 |
| raid-6 | 4 |

> **Warning**: Local NVMe is ephemeral. Do not **stop** instances (destroys data). Reboots are safe.

## Outputs

After deployment:

```bash
terraform output

# Key outputs:
# hammerspace_mgmt_url     = "https://10.0.1.100:443"
# hammerspace_dsx_private_ips = ["10.0.1.101", "10.0.1.102"]
# aurora_cluster_endpoint  = "cluster.xxx.us-west-2.rds.amazonaws.com"
# amazonmq_console_url     = "https://xxx.mq.us-west-2.amazonaws.com"
```

## Feature Matrix

For a complete list of all supported features and configuration options, see:

**[FEATURE_MATRIX.md](./FEATURE_MATRIX.md)**

This includes:
- Component deployment options
- Networking features
- Availability & placement settings
- Instance configuration
- Storage configuration (EBS, RAID, Tier-0)
- Volume groups & shares
- ECGroup (RozoFS) features
- AWS managed services (Aurora, Amazon MQ)
- IAM & security settings
- Pre-flight validation checks

## Pre-flight Validation

This configuration includes automatic validation during `terraform plan`:

| Category | Checks Performed |
|----------|------------------|
| **Networking** | VPC exists, subnets belong to VPC, AZs valid for region |
| **AMIs** | All AMIs exist and accessible in region |
| **Instance Types** | Types available in target AZs |
| **Aurora** | Dual-subnet setup for multi-AZ |
| **Amazon MQ** | All required credentials provided |

### Example Validation Errors

**AMI not found:**
```
Error: The specified AMI (ami-xxxxx) does not exist in region us-west-2
```

**Solution**: Verify the AMI ID is correct for your region. Hammerspace AMIs vary by region—check the [AWS Marketplace](https://aws.amazon.com/marketplace/pp/prodview-3foicv5pgwl46) for the correct AMI ID in your target region. Ensure you've subscribed to the Hammerspace AMI before deployment.

**Instance type unavailable:**
```
Error: Instance type m5zn.12xlarge is not available in us-west-2a
```

**Solution**: Not all instance types are available in every Availability Zone. Try one of the following:
- Change `subnet_1_az` or `subnet_2_az` to a different AZ in your region
- Use a different instance type (e.g., `m5.12xlarge` instead of `m5zn.12xlarge`)
- Check [AWS instance type availability](https://aws.amazon.com/ec2/instance-types/) for your region

## Troubleshooting

### Common Issues

#### "InsufficientInstanceCapacity" Error

```
Error: InsufficientInstanceCapacity: We currently do not have sufficient capacity
```

**Solutions**:
- Try a different Availability Zone
- Use a different instance type
- Reduce capacity reservation timeout:
  ```hcl
  capacity_reservation_create_timeout = "2m"
  ```

#### Placement Group Deletion Error

```
Error: InvalidPlacementGroup.InUse
```

**Solution**: Run `terraform destroy` a second time. First run terminates instances; second deletes the placement group.

#### OptInRequired Error

```
Error: OptInRequired: You are not subscribed to this service
```

**Solution**: Open the URL in the error, sign in to AWS, and accept the marketplace terms.

### Logs Location

- **Hammerspace**: `/var/log/hammerspace/`
- **Ansible**: Check via SSM Session Manager
- **Cloud-init**: `/var/log/cloud-init-output.log`

## Clean Up

```bash
# Destroy all resources
terraform destroy

# Destroy specific module
terraform destroy -target=module.ansible
terraform destroy -target=module.hammerspace
```

> **Note**: You may need to run `terraform destroy` twice due to placement group timing.

## File Structure

```
.
├── main.tf                    # Root module configuration
├── variables.tf               # Input variable definitions
├── outputs.tf                 # Output definitions
├── versions.tf                # Provider version constraints
├── terraform.tfvars           # Your configuration values
├── FEATURE_MATRIX.md          # Complete feature reference
├── README.md                  # This file
├── modules/
│   ├── hammerspace/           # Anvil + DSX deployment
│   ├── ecgroup/               # RozoFS cluster
│   ├── storage_servers/       # Generic storage with RAID
│   ├── clients/               # Client instances
│   ├── ansible/               # Automation controller
│   ├── aurora/                # Aurora database
│   ├── amazon_mq/             # RabbitMQ broker
│   └── iam-core/              # IAM roles and policies
└── ssh_keys/                  # SSH public keys directory
```

## License

Copyright (c) 2025-2026 Hammerspace, Inc

MIT License - See LICENSE file for details.

---

*For detailed feature information, see [FEATURE_MATRIX.md](./FEATURE_MATRIX.md)*
