# Terraform-AWS Feature Matrix

This document provides a comprehensive overview of all features and capabilities supported by this Terraform configuration.

---

## Table of Contents

- [Component Deployment](#component-deployment)
- [Networking](#networking)
- [Availability & Placement](#availability--placement)
- [Instance Configuration](#instance-configuration)
- [Storage Configuration](#storage-configuration)
- [Volume Groups & Shares (Hammerspace)](#volume-groups--shares-hammerspace)
- [ECGroup (RozoFS) Features](#ecgroup-rozofs-features)
- [Automation & Integration](#automation--integration)
- [AWS Managed Services](#aws-managed-services)
  - [Amazon MQ (RabbitMQ)](#amazon-mq-rabbitmq)
  - [Aurora Database](#aurora-database)
- [IAM & Security](#iam--security)
- [Quick Reference: deploy_components Options](#quick-reference-deploy_components-options)
- [Example Configurations](#example-configurations)
- [Pre-flight Validation Checks](#pre-flight-validation-checks)

---

## Component Deployment

| Feature | Supported | Variable | Description |
|---------|-----------|----------|-------------|
| Deploy Hammerspace Anvil (new) | ✅ Yes | `hammerspace_anvil_count = 1` | Deploy new standalone Anvil |
| Deploy Hammerspace Anvil HA | ✅ Yes | `hammerspace_anvil_count = 2` | Deploy 2 Anvils in HA mode |
| Deploy DSX Nodes | ✅ Yes | `hammerspace_dsx_count = N` | Deploy N DSX data service nodes |
| Deploy ECGroup (RozoFS) | ✅ Yes | `deploy_components = ["ecgroup"]` | Erasure-coded storage cluster |
| Deploy Storage Servers | ✅ Yes | `deploy_components = ["storage"]` | Generic storage server nodes |
| Deploy Client Instances | ✅ Yes | `deploy_components = ["clients"]` | NFS/SMB client instances |
| Deploy Ansible Controller | ✅ Yes | `ansible_instance_count = 1` | Automation controller node |
| Deploy Amazon MQ | ✅ Yes | `deploy_components = ["mq"]` | RabbitMQ message broker |
| Deploy Aurora Database | ✅ Yes | `deploy_components = ["aurora"]` | PostgreSQL/MySQL compatible DB |
| Deploy All Components | ✅ Yes | `deploy_components = ["all"]` | Deploy everything |

---

## Networking

| Feature | Supported | Variable | Description |
|---------|-----------|----------|-------------|
| Create New VPC | ✅ Yes | `vpc_cidr = "10.0.0.0/16"` | Auto-create VPC with full networking |
| Use Existing VPC | ✅ Yes | `vpc_id = "vpc-..."` | Use pre-existing VPC |
| Create New Subnets | ✅ Yes | `private_subnet_1_cidr`, `public_subnet_1_cidr` | Auto-create subnets |
| Use Existing Subnets | ✅ Yes | `private_subnet_id = "subnet-..."` | Use pre-existing subnets |
| Multiple Availability Zones | ✅ Yes | `subnet_1_az`, `subnet_2_az` | Multi-AZ deployment |
| Public IP Assignment | ✅ Yes | `assign_public_ip = true/false` | Assign public IPs |
| NAT Gateway (auto-created) | ✅ Yes | Automatic with new VPC | NAT for private instances |
| Internet Gateway (auto-created) | ✅ Yes | Automatic with new VPC | IGW for public subnets |
| Custom Security Groups | ✅ Yes | `hammerspace_anvil_security_group_id` | Use existing security groups |
| Allowed Source CIDR Blocks | ✅ Yes | `allowed_source_cidr_blocks` | Restrict ingress traffic |
| Route 53 Private Hosted Zone | ✅ Yes | `hosted_zone_name` | DNS for internal resources |

---

## Availability & Placement

| Feature | Supported | Variable | Description |
|---------|-----------|----------|-------------|
| Availability Zone Selection | ✅ Yes | `subnet_1_az`, `subnet_2_az` | Choose AZs for subnets |
| Placement Groups | ✅ Yes | `placement_group_name` | Cluster, spread, or partition |
| Placement Group Strategy | ✅ Yes | `placement_group_strategy = "cluster"` | cluster/spread/partition |
| Capacity Reservations | ✅ Yes | Automatic for all instance types | Reserved capacity per component |
| Capacity Reservation Timeout | ✅ Yes | `capacity_reservation_create_timeout = "5m"` | Wait time for reservation |
| Capacity Reservation Expiration | ✅ Yes | `capacity_reservation_expiration = "10m"` | Auto-expire reservations |

---

## Instance Configuration

| Feature | Supported | Variable | Description |
|---------|-----------|----------|-------------|
| Anvil Instance Type | ✅ Yes | `hammerspace_anvil_instance_type` | Default: m5zn.12xlarge |
| DSX Instance Type | ✅ Yes | `hammerspace_dsx_instance_type` | Default: m5.xlarge |
| ECGroup Instance Type | ✅ Yes | `ecgroup_instance_type` | Default: m6i.16xlarge |
| Client Instance Type | ✅ Yes | `clients_instance_type` | Custom client instances |
| Storage Instance Type | ✅ Yes | `storage_instance_type` | Custom storage instances |
| Ansible Instance Type | ✅ Yes | `ansible_instance_type` | Default: m5n.8xlarge |
| Custom AMI IDs | ✅ Yes | `hammerspace_ami`, `clients_ami`, etc. | Specific images per component |
| Custom AMI Owner IDs | ✅ Yes | `custom_ami_owner_ids` | Search private/community AMIs |
| AMI Pre-flight Checks | ✅ Yes | Automatic | Validates AMIs exist in region |
| Instance Type Validation | ✅ Yes | Automatic | Validates types available in AZ |

---

## Storage Configuration

| Feature | Supported | Variable | Description |
|---------|-----------|----------|-------------|
| **Anvil Metadata Disk** | | | |
| Metadata Disk Size | ✅ Yes | `hammerspace_anvil_meta_disk_size` | Default: 1000 GB |
| Metadata Disk Type | ✅ Yes | `hammerspace_anvil_meta_disk_type` | gp3, io2, etc. |
| Metadata Disk IOPS | ✅ Yes | `hammerspace_anvil_meta_disk_iops` | Performance tuning |
| Metadata Disk Throughput | ✅ Yes | `hammerspace_anvil_meta_disk_throughput` | Performance tuning |
| **DSX Data Volumes** | | | |
| DSX EBS Count | ✅ Yes | `hammerspace_dsx_ebs_count` | Volumes per DSX node |
| DSX EBS Size | ✅ Yes | `hammerspace_dsx_ebs_size` | Default: 200 GB |
| DSX EBS Type | ✅ Yes | `hammerspace_dsx_ebs_type` | gp3, io2, etc. |
| DSX EBS IOPS | ✅ Yes | `hammerspace_dsx_ebs_iops` | Performance tuning |
| DSX EBS Throughput | ✅ Yes | `hammerspace_dsx_ebs_throughput` | Performance tuning |
| Auto-add DSX Volumes | ✅ Yes | `hammerspace_dsx_add_vols = true` | Register volumes in Hammerspace |
| **Storage Server Volumes** | | | |
| Storage EBS Count | ✅ Yes | `storage_ebs_count` | Volumes per storage server |
| Storage EBS Size | ✅ Yes | `storage_ebs_size` | Default: 1000 GB |
| Storage EBS Type | ✅ Yes | `storage_ebs_type` | gp3, io2, etc. |
| Storage IOPS/Throughput | ✅ Yes | `storage_ebs_iops`, `storage_ebs_throughput` | Performance tuning |
| RAID Configuration | ✅ Yes | `storage_raid_level = "raid-0/5/6"` | RAID level for storage |
| **Client Volumes** | | | |
| Client EBS Count | ✅ Yes | `clients_ebs_count` | Volumes per client |
| Client EBS Size | ✅ Yes | `clients_ebs_size` | Default: 1000 GB |
| Client Tier0 RAID | ✅ Yes | `clients_tier0`, `clients_tier0_type` | Local RAID caching |
| **ECGroup Volumes** | | | |
| ECGroup Metadata Volume | ✅ Yes | `ecgroup_metadata_volume_size/type` | DRBD metadata storage |
| ECGroup Storage Volumes | ✅ Yes | `ecgroup_storage_volume_count/size` | Data storage volumes |
| ECGroup IOPS/Throughput | ✅ Yes | `ecgroup_*_volume_iops/throughput` | Performance tuning |

---

## Volume Groups & Shares (Hammerspace)

| Feature | Supported | Variable | Description |
|---------|-----------|----------|-------------|
| **DSX Volume Management** | ✅ Yes | `hammerspace_dsx_add_vols = true` | Auto-add DSX volumes to Anvil |
| **Storage Server Volume Groups** | ✅ Yes | `config_ansible.volume_groups` | Group storage server volumes |
| **Storage Server Shares** | ✅ Yes | `config_ansible.volume_groups[].share` | NFS/SMB share on storage VG |
| **ECGroup Volume Group** | ✅ Yes | `config_ansible.ecgroup_volume_group` | Group ECGroup volumes |
| **ECGroup Share** | ✅ Yes | `config_ansible.ecgroup_share_name` | NFS/SMB share on ECGroup VG |

### Ansible Configuration Structure

```hcl
config_ansible = {
  allow_root           = false
  ecgroup_volume_group = "ecg-vg"
  ecgroup_share_name   = "ecg-share"
  volume_groups = {
    "storage-vg" = {
      volumes    = ["1", "2"]          # Storage server indexes (1-based)
      add_groups = ["group1", "group2"] # Optional: additional AD groups
      share      = "storage-data"       # Share name
    }
  }
}
```

### Volume Group Workflow

```
┌───────────────────────────────────────────────────────────────────────────────┐
│                              Hammerspace Anvil                                │
│                           (Metadata Controller)                               │
└───────────────────────────────────────────────────────────────────────────────┘
                                       │
         ┌─────────────────────────────┼─────────────────────────────┐
         │                             │                             │
         ▼                             ▼                             ▼
┌─────────────────────┐   ┌─────────────────────┐   ┌─────────────────────┐
│     DSX Nodes       │   │   Storage Servers   │   │      ECGroup        │
│  (Hammerspace Data  │   │  (Generic Storage)  │   │   (RozoFS Cluster)  │
│     Services)       │   │                     │   │                     │
│                     │   │                     │   │                     │
│  ┌───────────────┐  │   │  ┌───────────────┐  │   │  ┌───────────────┐  │
│  │  EBS Volumes  │  │   │  │  EBS Volumes  │  │   │  │ RozoFS Volume │  │
│  │ (auto-added)  │  │   │  │               │  │   │  │               │  │
│  └───────────────┘  │   │  └───────────────┘  │   │  └───────────────┘  │
│         │           │   │         │           │   │         │           │
│         ▼           │   │         ▼           │   │         ▼           │
│  ┌───────────────┐  │   │  ┌───────────────┐  │   │  ┌───────────────┐  │
│  │ (Managed by   │  │   │  │ Volume Group  │  │   │  │ Volume Group  │  │
│  │  Anvil auto)  │  │   │  │  "storage-vg" │  │   │  │   "ecg-vg"    │  │
│  └───────────────┘  │   │  └───────────────┘  │   │  └───────────────┘  │
│                     │   │         │           │   │         │           │
│                     │   │         ▼           │   │         ▼           │
│                     │   │  ┌───────────────┐  │   │  ┌───────────────┐  │
│                     │   │  │    Share      │  │   │  │    Share      │  │
│                     │   │  │"storage-data" │  │   │  │  "ecg-share"  │  │
│                     │   │  └───────────────┘  │   │  └───────────────┘  │
└─────────────────────┘   └─────────────────────┘   └─────────────────────┘
```

---

## ECGroup (RozoFS) Features

| Feature | Supported | Variable | Description |
|---------|-----------|----------|-------------|
| ECGroup Node Deployment | ✅ Yes | `ecgroup_node_count = N` | 4-16 RozoFS nodes |
| Boot Volume Config | ✅ Yes | `ecgroup_boot_volume_size/type` | Root volume settings |
| Metadata Volumes | ✅ Yes | `ecgroup_metadata_volume_size` | DRBD metadata storage |
| Storage Volumes | ✅ Yes | `ecgroup_storage_volume_count/size` | Data storage volumes |
| Region-specific AMI | ✅ Yes | Automatic | Pre-configured AMI per region |
| Placement Group Support | ✅ Yes | `placement_group_name` | Cluster placement |

### Supported ECGroup Regions

| Region | AMI ID |
|--------|--------|
| eu-west-3 (Paris) | ami-0366b4547202afb15 |
| us-west-2 (Oregon) | ami-029d555d8523da58d |
| us-east-1 (Virginia) | ami-00d97e643a6091d85 |
| us-east-2 (Ohio) | ami-0542e5a5c7395ed56 |
| ca-central-1 (Canada) | ami-0f8e2a6ca6aeaaf0a |

---

## Automation & Integration

| Feature | Supported | Variable | Description |
|---------|-----------|----------|-------------|
| SSM Bootstrap | ✅ Yes | `use_ssm_bootstrap = true` | Use SSM for key distribution |
| Ansible Auto-Configuration | ✅ Yes | `ansible_instance_count = 1` | Automated setup via Ansible |
| Custom Authorized Keys | ✅ Yes | `authorized_keys` | SSH key content for instances |
| Ansible SSH Key Pair | ✅ Yes | `ansible_ssh_public_key` | Public key for Ansible |
| Ansible Private Key (Secrets Manager) | ✅ Yes | `ansible_private_key_secret_arn` | Private key from AWS Secrets |
| Target User Configuration | ✅ Yes | `*_target_user` | SSH user per component |

---

## AWS Managed Services

### Amazon MQ (RabbitMQ)

| Feature | Supported | Variable | Description |
|---------|-----------|----------|-------------|
| Deploy Amazon MQ | ✅ Yes | `deploy_components = ["mq"]` | RabbitMQ broker |
| Instance Type | ✅ Yes | `amazonmq_instance_type` | Default: mq.m5.large |
| Engine Version | ✅ Yes | `amazonmq_engine_version` | Default: 3.13 |
| Admin Credentials | ✅ Yes | `amazonmq_admin_username/password` | Broker admin user |
| Site Admin Credentials | ✅ Yes | `amazonmq_site_admin_*` | Site-level admin |
| Multi-AZ Deployment | ✅ Yes | Automatic | Requires 2 private subnets |

### Aurora Database

| Feature | Supported | Variable | Description |
|---------|-----------|----------|-------------|
| Deploy Aurora | ✅ Yes | `deploy_components = ["aurora"]` | Aurora cluster |
| Engine Type | ✅ Yes | `aurora_engine` | aurora-postgresql or aurora-mysql |
| Engine Version | ✅ Yes | `aurora_engine_version` | Specific version |
| Instance Class | ✅ Yes | `aurora_instance_class` | Default: db.r6g.large |
| Instance Count | ✅ Yes | `aurora_instance_count` | Default: 2 |
| Database Name | ✅ Yes | `aurora_db_name` | Initial database |
| Master Credentials | ✅ Yes | `aurora_master_username/password` | Admin credentials |
| Backup Retention | ✅ Yes | `aurora_backup_retention_days` | Default: 7 days |
| Backup Window | ✅ Yes | `aurora_preferred_backup_window` | UTC time window |
| Maintenance Window | ✅ Yes | `aurora_preferred_maintenance_window` | UTC time window |
| Deletion Protection | ✅ Yes | `aurora_deletion_protection` | Default: true |
| Storage Encryption | ✅ Yes | `aurora_storage_encrypted` | Default: true |
| KMS Key | ✅ Yes | `aurora_kms_key_id` | Custom encryption key |
| Performance Insights | ✅ Yes | `aurora_enable_performance_insights` | Monitoring |
| HTTP Endpoint (Data API) | ✅ Yes | `aurora_enable_http_endpoint` | Query via HTTPS |
| Event Notifications | ✅ Yes | `aurora_event_email` | SNS email alerts |
| Multi-AZ Deployment | ✅ Yes | Automatic | Requires 2 private subnets |

---

## IAM & Security

| Feature | Supported | Variable | Description |
|---------|-----------|----------|-------------|
| SSH Key Pair | ✅ Yes | `key_name` | EC2 key pair name |
| SSH Keys Directory | ✅ Yes | `ssh_keys_dir` | Directory with public keys |
| Allow Root Access | ✅ Yes | `allow_root = true/false` | Root SSH access |
| Custom IAM Profile | ✅ Yes | `iam_profile_name` | Use existing profile |
| IAM Role Path | ✅ Yes | `iam_role_path` | IAM role path |
| Additional IAM Policies | ✅ Yes | `iam_additional_policy_arns` | Extra policy ARNs |
| IAM Admin Group | ✅ Yes | `iam_admin_group_name` | SSH access group |
| Anvil Security Group | ✅ Yes | `hammerspace_anvil_security_group_id` | Custom SG for Anvil |
| DSX Security Group | ✅ Yes | `hammerspace_dsx_security_group_id` | Custom SG for DSX |
| Ansible Controller CIDR | ✅ Yes | `ansible_controller_cidr` | Restrict Ansible SSH |
| Standalone Anvil Destruction Safety | ✅ Yes | `hammerspace_sa_anvil_destruction` | Protect against accidental destroy |

---

## Quick Reference: deploy_components Options

```hcl
# Deploy specific components
deploy_components = ["hammerspace"]                    # Only Hammerspace (Anvil + DSX)
deploy_components = ["hammerspace", "ecgroup"]         # Hammerspace + ECGroup
deploy_components = ["hammerspace", "storage"]         # Hammerspace + Storage servers
deploy_components = ["hammerspace", "clients"]         # Hammerspace + Clients
deploy_components = ["hammerspace", "mq"]              # Hammerspace + Amazon MQ
deploy_components = ["hammerspace", "aurora"]          # Hammerspace + Aurora Database
deploy_components = ["all"]                            # Everything

# Available component options:
# - "hammerspace" : Anvil metadata server + DSX data services
# - "ecgroup"     : RozoFS erasure-coded storage cluster
# - "storage"     : Generic storage server instances
# - "clients"     : NFS/SMB client instances
# - "mq"          : Amazon MQ (RabbitMQ) message broker
# - "aurora"      : Aurora PostgreSQL/MySQL database
# - "all"         : Deploy all components
```

---

## Example Configurations

### Minimal Hammerspace Deployment (Anvil only)
```hcl
deploy_components         = ["hammerspace"]
hammerspace_anvil_count   = 1
hammerspace_dsx_count     = 0
ansible_instance_count    = 1
```

### Full Hammerspace with DSX
```hcl
deploy_components         = ["hammerspace"]
hammerspace_anvil_count   = 1
hammerspace_dsx_count     = 2
hammerspace_dsx_add_vols  = true
ansible_instance_count    = 1
```

### Hammerspace HA Deployment
```hcl
deploy_components         = ["hammerspace"]
hammerspace_anvil_count   = 2
hammerspace_dsx_count     = 4
ansible_instance_count    = 1
```

### Hammerspace + ECGroup Integration
```hcl
deploy_components       = ["hammerspace", "ecgroup"]
hammerspace_anvil_count = 1
hammerspace_dsx_count   = 0
ecgroup_node_count      = 4
ansible_instance_count  = 1

config_ansible = {
  allow_root           = false
  ecgroup_volume_group = "ecg-vg"
  ecgroup_share_name   = "ecg-data"
  volume_groups        = {}
}
```

### Hammerspace + Storage Servers
```hcl
deploy_components         = ["hammerspace", "storage"]
hammerspace_anvil_count   = 1
hammerspace_dsx_count     = 0
storage_instance_count    = 2
storage_ebs_count         = 4
storage_raid_level        = "raid-5"
ansible_instance_count    = 1

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

### Full Production Stack
```hcl
deploy_components         = ["hammerspace", "ecgroup", "storage", "clients", "mq", "aurora"]
hammerspace_anvil_count   = 2
hammerspace_dsx_count     = 4
ecgroup_node_count        = 4
storage_instance_count    = 2
clients_instance_count    = 4
ansible_instance_count    = 1

# With placement group for performance
placement_group_name      = "hammerspace-cluster"
placement_group_strategy  = "cluster"
```

### Using Existing VPC
```hcl
# Point to existing infrastructure
vpc_id            = "vpc-0123456789abcdef0"
private_subnet_id = "subnet-0123456789abcdef0"
public_subnet_id  = "subnet-fedcba9876543210f"

# For Aurora/MQ multi-AZ
private_subnet_2_id = "subnet-0987654321fedcba0"

deploy_components         = ["hammerspace"]
hammerspace_anvil_count   = 1
hammerspace_dsx_count     = 2
```

---

## Pre-flight Validation Checks

The Terraform configuration includes automatic validation for:

| Check | Description |
|-------|-------------|
| VPC Configuration | Validates VPC ID exists or CIDR is provided for creation |
| Subnet Configuration | Validates subnet IDs exist or CIDRs for creation |
| Availability Zone Validation | Validates AZs are valid for the region |
| AMI Existence | Validates all AMIs exist in the target region |
| Instance Type Availability | Validates instance types available in target AZ |
| Aurora Network Prerequisites | Validates dual-subnet setup for Aurora |
| Amazon MQ Credentials | Validates all required credentials are set |
| Network Conflict Detection | Prevents conflicting ID/CIDR configurations |

---

*Generated for Terraform-AWS project*
