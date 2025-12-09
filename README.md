# Terraform-AWS

Terraform-AWS is a modular Terraform project for provisioning **Hammerspace-based data environments in AWS**.

It can deploy:

* Linux **clients**
* Linux **storage servers**
* **Hammerspace** Anvil & DSX nodes
* **ECGroup** clusters
* **Amazon MQ (RabbitMQ)** brokers
* **Amazon Aurora** database clusters (PostgreSQL/MySQL)
* An **Ansible controller** for “Day 2” automation

Originally built for internal Hammerspace use to size Hammerspace resources for an LLM-based sizing engine, it has since evolved into a **general-purpose deployment framework** for customers who want to spin up full lab, POC, or production environments with strong guardrails.

> Guard-rails are built in to help less-experienced cloud users avoid painful misconfigurations, capacity issues, and long “hung” applies.

---

## 📚 Table of Contents

* [Installation](#installation)
* [Configuration](#configuration)

  * [Global Variables](#global-variables)
* [Component Variables](#component-variables)

  * [Client Variables](#client-variables)
  * [Storage Server Variables](#storage-server-variables)
  * [Hammerspace Variables](#hammerspace-variables)
  * [ECGroup Variables](#ecgroup-variables)
  * [Aurora Variables](#aurora-variables)
  * [AmazonMQ Variables](#amazonmq-variables)
  * [Ansible Variables](#ansible-variables)

    * [Generating and Storing SSH Keys for Ansible](#generating-and-storing-ssh-keys-for-ansible)
  * [Ansible Configuration Variables](#ansible-configuration-variables)
* [How to Use](#how-to-use)

  * [Local Development Setup (AWS Profile)](#local-development-setup-aws-profile)
* [Infrastructure Guardrails and Validation](#infrastructure-guardrails-and-validation)
* [Dealing with AWS Capacity and Timeouts](#dealing-with-aws-capacity-and-timeouts)

  * [Controlling API Retries (`max_retries`)](#controlling-api-retries-max_retries)
  * [Controlling Capacity Timeouts](#controlling-capacity-timeouts)
  * [Understanding the Timeout Behavior](#understanding-the-timeout-behavior)
  * [Important Warning on Capacity Reservation Billing](#important-warning-on-capacity-reservation-billing)
* [Required IAM Permissions for Custom Instance Profile](#required-iam-permissions-for-custom-instance-profile)
* [Securely Accessing Instances](#securely-accessing-instances)
* [Production Backend](#production-backend)
* [Tier-0](#tier-0)
* [Important Note on Placement Group Deletion](#important-note-on-placement-group-deletion)
* [Outputs](#outputs)
* [Modules](#modules)

---

## Installation

Before running this Terraform configuration, complete the following one-time setup tasks for the target AWS account.

### 1. Clone the Terraform-AWS Project

Pick any working directory on your local system:

```bash
mkdir -p ~/Terraform-Projects   # example
cd ~/Terraform-Projects
git clone https://github.com/hammerspace-solutions/Terraform-AWS.git
cd Terraform-AWS
```

### 2. Install Required Tools

You must have:

* [Terraform](https://developer.hashicorp.com/terraform/downloads)
* [AWS CLI](https://aws.amazon.com/cli/)

installed and configured on your system.

### 3. Subscribe to Required AWS Marketplace Products

This configuration uses partner AMIs (e.g., for Hammerspace) which may require an **AWS Marketplace subscription**.

If you see an `OptInRequired` error during `terraform apply`, the error will contain a URL. Open that URL in your browser, sign in, and accept the product terms. This is a **one-time operation per AWS account per product**.

### 4. Create AWS Credentials

Create an AWS credentials file for your account.

```bash
mkdir -p ~/.aws
cd ~/.aws
```

Create `credentials`:

```bash
vim credentials
# insert:
[default]
aws_access_key_id = INSERT-ACCESS-KEY-HERE
aws_secret_access_key = INSERT-SECRET-ACCESS-KEY-HERE
# save & exit
```

### 5. Create AWS Config

Create `config` in the same directory with your default region:

```bash
vim config
# insert:
[default]
region = us-east-1
# save & exit
```

### 6. Create `terraform.tfvars`

Create a `terraform.tfvars` file based on the provided example:

```bash
cp example_terraform.tfvars.rename terraform.tfvars
vim terraform.tfvars
```

At a minimum you must provide:

* `project_name`
* `vpc_id` (or VPC creation details in the current design)
* `subnet_id` / subnet configuration
* `key_name`
* Required `*_ami` variables (clients, storage, Hammerspace, ECGroup, Ansible, etc.)

Then refine based on the [Configuration](#configuration) and [Component Variables](#component-variables) sections below.

> **Note**
> If you do not have a vpc_id/subnet_id, then this module can create the VPC and subnet(s) for you. Please lookup the procedure in the [Global Variables](#global-variables) section below.

---

### Generating and Storing SSH Keys for Ansible

The Ansible controller uses an SSH key pair to securely configure target instances (clients, storage servers, ECGroup, etc.) over SSH. The **public key** is registered in AWS; the **private key** is stored in **AWS Secrets Manager**.

#### 1. Generate a Public/Private Key Pair

On your local machine:

```bash
ssh-keygen -t ed25519 -f ansible_controller_key -C "Ansible Controller Key"
```

This creates:

* `ansible_controller_key`     → **private key** (keep secret)
* `ansible_controller_key.pub` → **public key**

#### 2. Store the Private Key in AWS Secrets Manager

```bash
aws secretsmanager create-secret \
  --name ansible-controller-private-key \
  --description "Private SSH key for Ansible controller" \
  --secret-string file://ansible_controller_key \
  --region <region>
```

Take note of the secret ARN, e.g.:

```text
arn:aws:secretsmanager:<region>:<account-id>:secret:ansible-controller-private-key-abc123
```

#### 3. Update `terraform.tfvars`

Add:

```hcl
ansible_ssh_public_key         = "<contents of ansible_controller_key.pub>"
ansible_private_key_secret_arn = "<ARN from step 2>"
```

Example:

```hcl
ansible_ssh_public_key         = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... Ansible Controller Key"
ansible_private_key_secret_arn = "arn:aws:secretsmanager:us-west-2:123456789012:secret:ansible-controller-private-key-abc123"
```

To get the public key contents:

```bash
cat ansible_controller_key.pub
```

Copy the entire line (starting with `ssh-ed25519`) into `terraform.tfvars`.

---

### IAM Permissions

If you set `iam_profile_name` in `terraform.tfvars` to use an existing IAM instance profile, that profile must allow:

* Reading the private key from Secrets Manager
* SSM Session Manager access for control-plane operations

Example IAM policy snippet for the Ansible role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "SecretsRead",
      "Effect": "Allow",
      "Action": "secretsmanager:GetSecretValue",
      "Resource": "<ansible_private_key_secret_arn>"
    },
    {
      "Sid": "SSMAccess",
      "Effect": "Allow",
      "Action": [
        "ssm:DescribeAssociation",
        "ssm:GetDeployablePatchSnapshotForInstance",
        "ssm:GetDocument",
        "ssm:DescribeDocument",
        "ssm:GetManifest",
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:ListAssociations",
        "ssm:ListInstanceAssociations",
        "ssm:PutInventory",
        "ssm:PutComplianceItems",
        "ssm:PutConfigurePackageResult",
        "ssm:UpdateAssociationStatus",
        "ssm:UpdateInstanceAssociationStatus",
        "ssm:UpdateInstanceInformation",
        "ssm:SendCommand",
        "ssm:GetCommandInvocation",
        "ssm:ListCommands",
        "ssm:ListCommandInvocations",
        "ssm:StartSession",
        "ssm:TerminateSession",
        "ssm:ResumeSession",
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel",
        "ec2messages:AcknowledgeMessage",
        "ec2messages:DeleteMessage",
        "ec2messages:FailMessage",
        "ec2messages:GetEndpoint",
        "ec2messages:GetMessages",
        "ec2messages:SendReply"
      ],
      "Resource": "*"
    }
  ]
}
```

If `iam_profile_name` is **not** set, the `iam-core` module will create a suitable profile automatically.

> **Security tips**
>
> * Store the private key securely and delete the local copy once uploaded to Secrets Manager.
> * Restrict the secret using IAM (e.g., only the Ansible role can read it).
> * Use unique key pairs per environment where possible.

---

## Configuration

Configuration is managed through `terraform.tfvars` using variables defined in `variables.tf`.

To simplify setup, the repository includes:

```text
example_terraform.tfvars.rename
```

1. Rename it:

```bash
mv example_terraform.tfvars.rename terraform.tfvars
```

2. Edit it to match your environment.

The following sections explain **global** variables and **per-component** variables.

---

### Global Variables

These variables control top-level behavior:

* `capacity_reservation_create_timeout`
  Duration to wait for a capacity reservation to become active (Default: `"5m"`).

* `capacity_reservation_expiration`
  Lifetime of capacity reservations before expiration (Default: `"5m"`).

* `deploy_components`
  List of components to deploy. Valid values:
  `"all"`, `"clients"`, `"storage"`, `"hammerspace"`, `"ecgroup"`, `"mq"`, `"aurora"`, `"ansible"`.

* `assign_public_ip`
  If `true`, Ansible instances get public IPs; if `false`, only private.

* `iam_profile_name`
  Name of an **existing** IAM Instance Profile to use. If blank, a profile is created.

* `region`
  AWS region for all resources (Default: `"us-west-2"`).

* `allowed_source_cidr_blocks`
  Additional IPv4 CIDRs allowed ingress (e.g., corp VPN).

* `custom_ami_owner_ids`
  Additional AWS Account IDs to search for private/community AMIs.

* `vpc_id`
  VPC ID for the deployment (or use VPC creation mode per current code).

* `subnet_id`
  Subnet ID for resources (or subnet-creation mode depending on design).

* `public_subnet_id`
  Public subnet ID for instances requiring public IPs. Required if `assign_public_ip = true`.

* `vpc_cidr`
  As an alternative to the vpc_id, you can create your own VPC by supplying the CIDR
  for an address range. The format is `10.10.1.0/16` (as an example). This is a range in which you will then create your subnet(s) (see next)

* `private_subnet_1_cidr`
  This is a CIDR for a subnet in which only private addresses are allocated.

* `private_subnet_2_cidr`
  This is a CIDR for a subnet in which only private addresses are allocated.

* `public_subnet_1_cidr`
  This is a CIDR for a subnet in which only public addresses are allocated. See `allow_public_ip` above.

* `public_subnet_1_cidr`
  This is a CIDR for a subnet in which only public addresses are allocated. See `allow_public_ip` above.

* `subnet_1_az`
  This is the name of the availability zone where the private and public subnet for segment 1 will be created. Example: `us-west-2a`

* `subnet_2_az`
  This is the name of the availability zone where the private and public subnet for segment 2 will be created. Example: `us-west-2b`

> **Note**
> We need to create private and public IP(s) in two availability zones for several of the modules (MQ and Aurora). Although you may never utilize these modules or features of this Terraform, we have not taken the time to design that into this Terraform. Hence, you are required to supply both public and private AZ and subnet CIDR(s).

> **Warning**
> You can either utilize an existing vpc_id or create your own. You cannot define both

* `key_name`
  EC2 key pair name.

* `tags`
  Common tags for all resources (Default: `{}`).

* `project_name`
  Project name for tagging and naming.

* `ssh_keys_dir`
  Directory containing SSH public keys (Default: `"./ssh_keys"`).

* `placement_group_name`
  Optional placement group name. If blank, no placement group is used.

* `placement_group_strategy`
  Placement group strategy: `"cluster"`, `"spread"`, or `"partition"` (Default: `"cluster"`).

---

## Component Variables

### Client Variables

Prefixed with `clients_` in `terraform.tfvars`:

* `clients_instance_count`
* `clients_tier0` – `""`, `"raid-0"`, `"raid-5"`, or `"raid-6"`.
* `clients_tier0_type` – RAID type for Tier-0 (Default: `"raid-0"`).
* `clients_ami`
* `clients_instance_type`
* `clients_boot_volume_size` (Default: `100`)
* `clients_boot_volume_type` (Default: `"gp2"`)
* `clients_ebs_count` (Default: `0`)
* `clients_ebs_size` (Default: `1000`)
* `clients_ebs_type` (Default: `"gp3"`)
* `clients_ebs_throughput`
* `clients_ebs_iops`
* `clients_target_user` (Default: `"ubuntu"`)

---

### Storage Server Variables

Prefixed with `storage_`:

* `storage_instance_count` (Default: `0`)
* `storage_ami` (**required**)
* `storage_instance_type`
* `storage_boot_volume_size` (Default: `100`)
* `storage_boot_volume_type` (Default: `"gp2"`)
* `storage_ebs_count` (Default: `0`)
* `storage_ebs_size` (Default: `1000`)
* `storage_ebs_type` (Default: `"gp3"`)
* `storage_ebs_throughput`
* `storage_ebs_iops`
* `storage_target_user` (Default: `"ubuntu"`)
* `storage_raid_level` – `"raid-0"`, `"raid-5"`, `"raid-6"` (Default: `"raid-5"`)

---

### Hammerspace Variables

Prefixed with `hammerspace_`:

* `hammerspace_anvil_security_group_id` (optional)
* `hammerspace_dsx_security_group_id` (optional)
* `hammerspace_ami`
* `hammerspace_iam_admin_group_id`
* `hammerspace_anvil_count`
  `0 = none`, `1 = standalone`, `2 = HA` (Default: `0`).
* `hammerspace_sa_anvil_destruction`
  Safety switch; must be `true` to destroy a standalone Anvil.
* `hammerspace_anvil_instance_type` (Default: `"m5zn.12xlarge"`)
* `hammerspace_dsx_instance_type` (Default: `"m5.xlarge"`)
* `hammerspace_dsx_count` (Default: `1`)
* `hammerspace_anvil_meta_disk_size` (Default: `1000`)
* `hammerspace_anvil_meta_disk_type` (Default: `"gp3"`)
* `hammerspace_anvil_meta_disk_throughput`
* `hammerspace_anvil_meta_disk_iops`
* `hammerspace_dsx_ebs_size` (Default: `200`)
* `hammerspace_dsx_ebs_type` (Default: `"gp3"`)
* `hammerspace_dsx_ebs_iops`
* `hammerspace_dsx_ebs_throughput`
* `hammerspace_dsx_ebs_count` (Default: `1`)
* `hammerspace_dsx_add_vols` (Default: `true`)

---

### ECGroup Variables

Prefixed with `ecgroup_`:

* `ecgroup_instance_type` (Default: `"m6i.16xlarge"`)
* `ecgroup_node_count` (Default: `4`, between 4 and 16)
* `ecgroup_boot_volume_size` (Default: `100`)
* `ecgroup_boot_volume_type` (Default: `"gp2"`)
* `ecgroup_metadata_volume_size` (Default: `4096`)
* `ecgroup_metadata_volume_type` (Default: `"io2"`)
* `ecgroup_metadata_volume_throughput`
* `ecgroup_metadata_volume_iops`
* `ecgroup_storage_volume_count` (Default: `4`)
* `ecgroup_storage_volume_size` (Default: `4096`)
* `ecgroup_storage_volume_type` (Default: `"gp3"`)
* `ecgroup_storage_volume_throughput`
* `ecgroup_storage_volume_iops`

---

### Aurora Variables

The Aurora module provisions an **Amazon Aurora** database cluster (PostgreSQL or MySQL) with:

* A dedicated **security group**
* A **DB subnet group** spanning two private subnets
* An **Aurora DB cluster** (writer endpoint)
* One or more **Aurora cluster instances** (readers/writer)
* Optional **RDS event notifications** via SNS + email

To enable Aurora, add `"aurora"` to `deploy_components` and set the following variables (prefixed with `aurora_`):

#### Networking & Placement

* `private_subnet_1_id`
  First **private** subnet ID for the Aurora DB subnet group (typically in AZ A).

* `private_subnet_2_id`
  Second **private** subnet ID for the Aurora DB subnet group (typically in AZ B).

> **Note**
> The module looks up the VPC CIDR via `vpc_id` (global variable) and allows inbound DB traffic from the VPC plus any `allowed_source_cidr_blocks`.

> **Note**
> If you do not have a VPC already defined, this module will create one for you. Please
> read about creating a VPC and Subnet(s) in the [Global Variables](#global-variables) section.

#### Engine & Sizing

* `aurora_engine` (Default: `"aurora-postgresql"`)
  Aurora engine type. Valid values:

  * `"aurora-postgresql"`
  * `"aurora-mysql"`

* `aurora_engine_version` (Default: `"15.3"`)
  Aurora engine version. If set to `""`, AWS chooses a default.

* `aurora_instance_class` (Default: `"db.r6g.large"`)
  Aurora instance class (e.g., `"db.r6g.large"`, `"db.r7g.large"`).

* `aurora_instance_count` (Default: `2`)
  Number of Aurora instances in the cluster (must be ≥ 1).

* `aurora_db_name` (Default: `"projecthouston"`)
  Initial database name in the Aurora cluster.

* `aurora_master_username` (**required**)
  Master username for Aurora.

* `aurora_master_password` (**required**, sensitive)
  Master password for Aurora.

#### Durability, Backups, Maintenance

* `aurora_backup_retention_days` (Default: `7`)
  How many days to retain automated backups.

* `aurora_preferred_backup_window` (Default: `"04:00-05:00"`)
  Preferred backup window (UTC), e.g. `"04:00-05:00"`.

* `aurora_preferred_maintenance_window` (Default: `"sun:06:00-sun:07:00"`)
  Preferred maintenance window (UTC), e.g. `"sun:06:00-sun:07:00"`.

* `aurora_deletion_protection` (Default: `true`)
  Enables deletion protection on the Aurora cluster.

* `aurora_storage_encrypted` (Default: `true`)
  Encrypt Aurora storage.

* `aurora_kms_key_id` (Default: `""`)
  KMS key ID/ARN for encryption. If empty and `aurora_storage_encrypted = true`, the AWS default KMS key is used.

* `aurora_skip_final_snapshot` (Default: `true`)
  Whether to skip creating a final snapshot when destroying the cluster.

* `aurora_final_snapshot_identifier` (Default: `""`)
  Identifier for the final snapshot when destroying the cluster.
  Must be **non-empty** if `aurora_skip_final_snapshot = false`.

#### Performance Insights

* `aurora_enable_performance_insights` (Default: `true`)
  Enable Performance Insights for Aurora instances.

* `aurora_performance_insights_retention_period` (Default: `7`)
  Performance Insights retention in days (e.g., `7`, `731`, `1095`).

* `aurora_performance_insights_kms_key_id` (Default: `""`)
  KMS key ID/ARN for Performance Insights (optional).

#### Data API (HTTP Endpoint)

* `aurora_enable_http_endpoint` (Default: `false`)
  Enable the Aurora Data API (HTTP endpoint) for the cluster.
  Useful for serverless or non-EC2 clients using HTTPS instead of direct TCP.

#### Event Notifications

* `aurora_event_email` (Default: `""`)
  Email address to receive Aurora/RDS events.
  If non-empty, the module creates:

  * An SNS topic `${project_name}-aurora-events`
  * An email subscription to that topic
  * A DB event subscription for the Aurora cluster

If `aurora_event_email` is empty, no event-related resources are created.

---

### AmazonMQ Variables

Prefixed with `amazonmq_`:

* `amazonmq_engine_version` – RabbitMQ version (Default: `"3.11"`)
* `amazonmq_instance_type` – Broker instance type (Default: `"mq.m5.large"`)
* `amazonmq_admin_username`
* `amazonmq_admin_password`
* `amazonmq_site_admin_username`
* `amazonmq_site_admin_password`
* `amazonmq_site_admin_password_hash` – precomputed RabbitMQ password hash

---

### Ansible Variables

Prefixed with `ansible_`:

> **Note**
> These variables configure the **Ansible controller instance** itself. What Ansible does afterward (playbooks, Day 2 operations) is controlled by the **Ansible configuration variables** in the next section.

* `ansible_instance_count` (Default: `1`)
* `ansible_ami` (**required**)
* `ansible_instance_type` (Default: `"m5n.8xlarge"`)
* `ansible_boot_volume_size` (Default: `100`)
* `ansible_boot_volume_type` (Default: `"gp2"`)
* `ansible_target_user` (Default: `"ubuntu"`)
* `ansible_ssh_public_key`
* `ansible_private_key_secret_arn`
* `ansible_controller_cidr` – fallback CIDR allowed for SSH ingress

---

### Ansible Configuration Variables

These variables drive how the Ansible controller configures Hammerspace, ECGroup, and storage volumes.

Configuration is supplied as a **JSON-like Terraform map**:

```hcl
config_ansible = {
  allow_root           = true
  ecgroup_volume_group = "xyz"
  ecgroup_share_name   = "123"
  volume_groups = {
    group_1 = {
      volumes = ["1","2","3","4"]
      share   = "group_1_share"
    }
    group_2 = {
      add_groups = ["group_1"]
      volumes    = ["5","6","7","8"]
      share      = "group_2_share"
    }
    group_3 = {
      add_groups = ["group_1", "group_2"]
      volumes    = ["9","10","11","12"]
      share      = "group_3_share"
    }
  }
}
```

* `allow_root`
  If `true`, Ansible will configure passwordless SSH between nodes **for the `root` user** (useful for testing/benchmarking).

* `ecgroup_volume_group` (optional)
  Volume group name to create if ECGroup is deployed.

* `ecgroup_share_name` (optional)
  Share name to create on top of the ECGroup volume group.

* `volume_groups` (optional)
  Map of volume group definitions:

  * `group_1`, `group_2`, etc. – logical names for volume groups.
  * `volumes` – list of storage server indices that belong to the group.
  * `share` – share name bound to that group.
  * `add_groups` – list of previously defined volume groups to include (e.g. composing multiple groups).

> **Note**
> Volume Groups and Shares are only created if you have configured **both** `storage` and `hammerspace` in `deploy_components`.

---

## How to Use

Once configured:

1. **Initialize**:

   ```bash
   terraform init
   ```

2. **Validate**:

   ```bash
   terraform validate
   ```

3. **Plan**:

   ```bash
   terraform plan
   ```

4. **Apply**:

   ```bash
   terraform apply
   ```

---

### Local Development Setup (AWS Profile)

To use a **named AWS profile** locally without affecting CI/CD, you can add a `local_override.tf` that is **not committed** to version control.

1. Create `local_override.tf` in the project root:

   ```hcl
   # Terraform-AWS/local_override.tf
   # Local-only provider overrides; do not commit this.

   provider "aws" {
     profile = "your-profile-name"
   }
   ```

2. Terraform will automatically merge this provider block when run locally.
   CI/CD environments that don’t have this file will fall back to their own configured credentials.

---

## Infrastructure Guardrails and Validation

To prevent common misconfigurations, this project includes **pre-flight checks** evaluated during `terraform plan`:

* **Network Validation**

  * Validates that `vpc_id` and subnet configuration refer to real resources in the selected region.
  * Confirms that subnets actually belong to the given VPC.

* **Resource Availability**

  * Verifies that requested EC2 instance types are available in the target Availability Zone(s).
  * Validates that AMI IDs (clients, storage, Hammerspace, Ansible, ECGroup, etc.) exist and are accessible (including private/partner AMIs via `custom_ami_owner_ids`).

* **Capacity & Provisioning Guardrails**

  * Uses **On-Demand Capacity Reservations** so capacity failures surface quickly rather than causing Terraform to hang.
  * Protects a standalone Anvil with a `lifecycle` rule; you must explicitly set `sa_anvil_destruction = true` to destroy it.

---

## Dealing with AWS Capacity and Timeouts

When using larger or specialized instance types, you may see `InsufficientInstanceCapacity` errors. This project includes knobs to tune behavior.

### Controlling API Retries (`max_retries`)

By default, the AWS provider retries transient errors, which can prolong failures. For **debugging capacity issues**, you can set:

```hcl
provider "aws" {
  region      = var.region
  max_retries = 0
}
```

This causes retryable errors to fail immediately.

### Controlling Capacity Timeouts

Capacity reservations are created first to ensure instances will launch. You can control the **wait time** using:

* `capacity_reservation_create_timeout` – how long Terraform waits for the reservation to become `active` (Default: `"5m"`).

### Understanding the Timeout Behavior

Even with `max_retries = 0`, the AWS provider may still take up to the timeout to fail, because:

1. Terraform requests a capacity reservation.
2. AWS returns success but sets reservation status to `pending`.
3. Terraform polls AWS waiting for the reservation to become `active`.
4. If it does not become `active` before `capacity_reservation_create_timeout`, Terraform fails the `apply`.

So `capacity_reservation_create_timeout` bounds **how long you’re willing to wait for capacity**.

### Important Warning on Capacity Reservation Billing

> **Warning**
> On-Demand Capacity Reservations start billing as soon as they’re created, even if **no instances** are running against them.

* `capacity_reservation_expiration` controls how quickly reservations expire (default `5m`), minimizing cost.
* Once a reservation expires, **increasing** the number of clients/storage nodes later may require **new reservations**, which may attempt to recreate or adjust existing resources.
* If you scale **within** an existing active reservation window, the adjustments are typically smoother.

---

## Required IAM Permissions for Custom Instance Profile

If you supply `iam_profile_name` (an existing instance profile), the associated IAM role must allow:

1. Discovering SSH keys/users from IAM if used.
2. Discovering EC2 instances and tags.
3. Managing floating IPs for Hammerspace HA.
4. Reporting usage for AWS Marketplace-based AMIs.

Example policy:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "SSHKeyAccess",
            "Effect": "Allow",
            "Action": [
                "iam:ListSSHPublicKeys",
                "iam:GetSSHPublicKey",
                "iam:GetGroup"
            ],
            "Resource": "arn:aws:iam::*:user/*"
        },
        {
            "Sid": "HAInstanceDiscovery",
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeInstances",
                "ec2:DescribeInstanceAttribute",
                "ec2:DescribeTags"
            ],
            "Resource": "*"
        },
        {
            "Sid": "HAFloatingIP",
            "Effect": "Allow",
            "Action": [
                "ec2:AssignPrivateIpAddresses",
                "ec2:UnassignPrivateIpAddresses"
            ],
            "Resource": "*"
        },
        {
            "Sid": "MarketplaceMetering",
            "Effect": "Allow",
            "Action": "aws-marketplace:MeterUsage",
            "Resource": "*"
        }
    ]
}
```

---

## Securely Accessing Instances

By default, the security model avoids opening instances to the internet:

Ingress is allowed only from:

1. The **VPC CIDR** itself (for internal communication).
2. Any additional CIDRs in `allowed_source_cidr_blocks` (e.g., VPN/management ranges).

This provides a secure baseline while still allowing flexible access control.

---

## Production Backend

For production, you should use a **remote backend** (e.g., S3 + DynamoDB) for state storage and locking.

Example `backend.tf`:

```hcl
terraform {
  backend "s3" {
    bucket         = "my-terraform-state-bucket"
    key            = "hammerspace/production/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
```

### One-Time Backend Setup

```bash
# Create S3 bucket
aws s3api create-bucket \
  --bucket my-terraform-state-bucket \
  --region us-west-2 \
  --create-bucket-configuration LocationConstraint=us-west-2

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket my-terraform-state-bucket \
  --versioning-configuration Status=Enabled

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
  --region us-west-2
```

---

## Tier-0

Tier-0 enables using **local NVMe storage inside client EC2 instances** as a high-performance storage tier managed by Hammerspace.

Typical AI workloads (training, checkpointing, inference, agentic workflows) require:

* High throughput
* Low latency
* Large unstructured data sets

Instead of relying solely on external flash arrays and heavy network infrastructure, **Tier-0 activates local NVMe** and uses Hammerspace to expose it as a shared, managed tier.

To enable Tier-0:

1. Choose instance types with local NVMe.
2. Set `clients_tier0` to one of:

   * `"raid-0"`
   * `"raid-5"`
   * `"raid-6"`

> **Note**
>
> Minimum NVMe disk counts per RAID level:
>
> | RAID   | Required NVMe Disks |
> | ------ | ------------------- |
> | raid-0 | 2                   |
> | raid-5 | 3                   |
> | raid-6 | 4                   |

> **Warning**
> Local NVMe is **ephemeral**. **Do not stop** instances in the AWS console; this destroys the underlying disks and the Tier-0 array.
> Reboots are safe; full stops are not.

---

## Important Note on Placement Group Deletion

When running `terraform destroy`, you may see:

```text
Error: InvalidPlacementGroup.InUse: The placement group ... is in use and may not be deleted.
```

This is due to an AWS race condition: Terraform tries to delete the placement group while EC2 instances are still being torn down.

**Workaround:** run `terraform destroy` **a second time**.
The first run terminates instances; the second deletes the now-empty placement group.

---

## Outputs

After a successful `terraform apply`, outputs include:

* `client_instances` – non-sensitive client instance details (ID, IP, Name).
* `storage_instances` – non-sensitive storage instance details.
* `hammerspace_anvil` – **sensitive**: Anvil details.
* `hammerspace_dsx` – **sensitive**: DSX details.
* `hammerspace_dsx_private_ips` – DSX private IPs.
* `hammerspace_mgmt_url` – Hammerspace management URL.
* `ecgroup_nodes` – ECGroup node details.
* `ansible_details` – Ansible controller details.
* `amazonmq_broker_id` - **sensitive**: ID of the Amazon MQ Broker
* `amazonmq_broker_arn` - **sensitive**: ARN of the Amazon MQ Broker
* `amazonmq_security_group_id` - **sensitive**: Security Group ID for the Amazon MQ Broker
* `amazonmq_amqps_endpoint` - Endpoint used by applications to talk to the Amazon MQ Broker
* `amazonmq_console_url` - Web address of the Amazon MQ Broker console
* `amazonmq_hosted_zone_id` - Route 53 hosted zone ID needed by the Amazon MQ Broker
* `aurora_cluster_endpoint` – Writer endpoint for the Aurora cluster (use for reads and writes).
* `aurora_reader_endpoint` – Reader endpoint for the Aurora cluster (use for read-only traffic).
* `aurora_security_group_id` – Security group ID associated with Aurora.
* `aurora_cluster_id` – **sensitive**: Aurora cluster ID/identifier.
* `aurora_cluster_arn` – **sensitive**: Aurora cluster ARN.

Use:

```bash
terraform output
terraform output <output_name>
```

for more information (sensitive values require the second form).

---

## Modules

This project is composed of several Terraform modules:

* **clients**
  Deploys client EC2 instances.

* **storage_servers**
  Deploys storage EC2 instances with RAID and export configuration.

* **hammerspace**
  Deploys Hammerspace Anvil (metadata) and DSX (data) nodes.

* **ecgroup**
  Deploys an ECGroup storage cluster using erasure coding.

* **aurora** (when enabled)
  Deploys an Amazon Aurora database cluster (PostgreSQL or MySQL) including:

  * Security group allowing DB access from the VPC and configured CIDRs.
  * DB subnet group spanning two private subnets.
  * Aurora cluster with encrypted storage, backups, and maintenance windows.
  * N Aurora instances with optional Performance Insights.
  * Optional RDS event notifications via SNS + email.

* **ansible**
  Deploys an Ansible controller that:

  * Integrates Hammerspace with storage servers (add data nodes, create volume group + share).
  * Configures the ECGroup cluster and its services.
  * Orchestrates passwordless SSH between client/storage nodes for automation.

* **amazon_mq** (when enabled)
  Deploys an Amazon MQ (RabbitMQ) broker and supporting DNS/security infrastructure for site ↔ central message flow.

---

Happy Terraforming! 🌩️
