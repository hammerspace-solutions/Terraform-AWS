# Terraform-AWS
This project uses Terraform to provision resources on AWS. The deployment is modular, allowing you to deploy client machines, storage servers, and a Hammerspace environment either together or independently.

This project was originally written for internal Hammerspace use to size Hammerspace resources within AWS for inclusion in a LLM model for automated AI sizing. It has since expanded to allow customers to deploy linux clients, linux storage servers, EC Groups, and Hammerspace Anvil's and DSX's for any use that they wish.

Guard-rails have been added to make sure that the deployments are as easy as possible for the uninitiated cloud user.

## Table of Contents
- [Configuration](#configuration)
  - [Global Variables](#global-variables)
- [Component Variables](#component-variables)
  - [Client Variables](#client-variables)
  - [Storage Server Variables](#storage-server-variables)
  - [Hammerspace Variables](#hammerspace-variables)
  - [ECGroup Variables](#ecgroup-variables)
  - [Ansible Variables](#ansible-variables)
- [Infrastructure Guardrails and Validation](#infrastructure-guardrails-and-validation)
- [Dealing with AWS Capacity and Timeouts](#dealing-with-aws-capacity-and-timeouts)
  - [Controlling API Retries (`max_retries`)](#controlling-api-retries-max_retries)
  - [Controlling Capacity Timeouts](#controlling-capacity-timeouts)
  - [Understanding the Timeout Behavior](#understanding-the-timeout-behavior)
  - [Important Warning on Capacity Reservation Billing](#important-warning-on-capacity-reservation-billing)
- [Required IAM Permissions for Custom Instance Profile](#required-iam-permissions-for-custom-instance-profile)
- [Securely Accessing Instances](#securely-accessing-instances)
  - [Option 1: Bastion Host (Recommended)](#option-1-bastion-host-recommended)
  - [Option 2: AWS Systems Manager Session Manager (Most Secure)](#option-2-aws-systems-manager-session-manager-most-secure)
- [Production Backend](#production-backend)
- [Prerequisites](#prerequisites)
- [How to Use](#how-to-use)
  - [Local Development Setup (AWS Profile)](#local-development-setup-aws-profile)
- [Important Note on Placement Group Deletion](#important-note-on-placement-group-deletion)
- [Outputs](#outputs)
- [Modules](#modules)


## Configuration

Configuration is managed through `terraform.tfvars` by setting values for the variables defined in `variables.tf`. In order to make it a little easier
for the user, we have supplied an `example_terraform.tfvars` file with all of the possible values. Just rename that file to terraform.tfvars and edit it to indicate
what you would like to configure. The global and module variables are explained in detail below.

### Global Variables

These variables apply to the overall deployment:

* `region`: AWS region for all resources (Default: "us-west-2").
* `assign_public_ip`: If `true`, assigns a public IP address to all created EC2 instances. If `false`, only a private IP will be assigned. (Default: `false`).
* `vpc_id`: (Required) VPC ID for all resources.
* `subnet_id`: (Required) Subnet ID for resources. The Availability Zone is automatically derived from this subnet.
* `key_name`: (Required) SSH key pair name for instance access.
* `tags`: Common tags to apply to all resources (Default: `{}`).
* `project_name`: (Required) Project name used for tagging and resource naming.
* `ssh_keys_dir`: A local directory for public SSH key files (`.pub`). The startup script automatically adds these keys to the `authorized_keys` file on all servers. (Default: `"./ssh_keys"`).
* `deploy_components`: List of components to deploy (e.g., `["clients", "storage"]` or `["all"]`) (Default: `["all"]`).
* `placement_group_name`: (Optional) The name of the placement group to create and launch instances into.
* `placement_group_strategy`: The strategy for the placement group: `cluster`, `spread`, or `partition` (Default: `cluster`).
* `capacity_reservation_create_timeout`: The maximum time to wait for a capacity reservation to be fulfilled before failing (e.g., `"5m"`). (Default: `"5m"`).
* `custom_ami_owner_ids`: A list of additional AWS Account IDs to search for AMIs. Use this for private or partner AMIs. (Default: `[]`).
* `allowed_source_cidr_blocks`: A list of additional IPv4 CIDR ranges to allow ingress traffic from (e.g., your corporate VPN range). The VPC's own CIDR block is automatically included.

---

## Component Variables

### Client Variables

These variables configure the client instances and are prefixed with `clients_` in your `terraform.tfvars` file.

* `clients_instance_count`: Number of client instances (Default: `1`).
* `clients_ami`: (Required) AMI for client instances.
* `clients_instance_type`: Instance type for clients (Default: `"m5n.8xlarge"`).
* `clients_boot_volume_size`: Root volume size (GB) (Default: `100`).
* `clients_boot_volume_type`: Root volume type (Default: `"gp2"`).
* `clients_ebs_count`: Number of extra EBS volumes per client (Default: `1`).
* `clients_ebs_size`: Size of each EBS volume (GB) (Default: `1000`).
* `clients_ebs_type`: Type of EBS volume (Default: `"gp3"`).
* `clients_ebs_throughput`: Throughput for gp3 EBS volumes (MB/s).
* `clients_ebs_iops`: IOPS for gp3/io1/io2 EBS volumes.
* `clients_user_data`: Path to user data script for clients.
* `clients_target_user`: Default system user for client EC2s (Default: `"ubuntu"`).
* `clients_tier0`: Tier-0 RAID on NVMe instance-store.
  * **Valid Values**: `""` (no RAID), `raid-0`, `raid-5`, `raid-6` (Default: `""`)
  * When set, Terrform detects all locally attached NVMe disks on the instance. The startup script then configures a RAID array at the chosen level (raid-0 = strip, raid-5 = parity, raid-6 = double parity).

---

### Storage Server Variables

These variables configure the storage server instances and are prefixed with `storage_` in your `terraform.tfvars` file.

* `storage_instance_count`: Number of storage instances (Default: `1`).
* `storage_ami`: (Required) AMI for storage instances.
* `storage_instance_type`: Instance type for storage (Default: `"m5n.8xlarge"`).
* `storage_boot_volume_size`: Root volume size (GB) (Default: `100`).
* `storage_boot_volume_type`: Root volume type (Default: `"gp2"`).
* `storage_ebs_count`: Number of extra EBS volumes per server for RAID (Default: `1`).
* `storage_ebs_size`: Size of each EBS volume (GB) (Default: `1000`).
* `storage_ebs_type`: Type of EBS volume (Default: `"gp3"`).
* `storage_ebs_throughput`: Throughput for gp3 EBS volumes (MB/s).
* `storage_ebs_iops`: IOPS for gp3/io1/io2 EBS volumes.
* `storage_user_data`: Path to user data script for storage.
* `storage_target_user`: Default system user for storage EC2s (Default: `"ubuntu"`).
* `storage_raid_level`: RAID level to configure: `raid-0`, `raid-5`, or `raid-6` (Default: `"raid-5"`).

---

### Hammerspace Variables

These variables configure the Hammerspace deployment and are prefixed with `hammerspace_` in `terraform.tfvars`.

* **`hammerspace_profile_id`**: Controls IAM Role creation.
    * **For users with restricted IAM permissions**: An admin must pre-create an IAM Instance Profile and provide its name here. Terraform will use the existing profile.
    * **For admin users**: Leave this variable as `""` (blank). Terraform will automatically create the necessary IAM Role and Instance Profile.
* **`hammerspace_anvil_security_group_id`**: (Optional) The ID of a pre-existing security group to attach to the Anvil nodes. If left blank, the module will create and configure a new security group.
* **`hammerspace_dsx_security_group_id`**: (Optional) The ID of a pre-existing security group to attach to the DSX nodes. If left blank, the module will create and configure a new security group.
* `hammerspace_ami`: AMI ID for Hammerspace instances (Default: example for CentOS 7).
* `hammerspace_iam_admin_group_id`: IAM admin group for SSH access.
* `hammerspace_anvil_count`: Number of Anvil instances (0=none, 1=standalone, 2=HA) (Default: `0`).
* `hammerspace_anvil_instance_type`: Instance type for Anvil (Default: `"m5zn.12xlarge"`).
* `hammerspace_dsx_instance_type`: Instance type for DSX nodes (Default: `"m5.xlarge"`).
* `hammerspace_dsx_count`: Number of DSX instances (Default: `1`).
* `hammerspace_anvil_meta_disk_size`: Metadata disk size in GB for Anvil (Default: `1000`).
* `hammerspace_anvil_meta_disk_type`: EBS volume type for Anvil metadata disk (Default: `"gp3"`).
* `hammerspace_anvil_meta_disk_throughput`: Throughput for Anvil metadata disk.
* `hammerspace_anvil_meta_disk_iops`: IOPS for Anvil metadata disk.
* `hammerspace_dsx_ebs_size`: Size of each EBS Data volume per DSX node (Default: `200`).
* `hammerspace_dsx_ebs_type`: Type of each EBS Data volume for DSX (Default: `"gp3"`).
* `hammerspace_dsx_ebs_iops`: IOPS for each EBS Data volume for DSX.
* `hammerspace_dsx_ebs_throughput`: Throughput for each EBS Data volume for DSX.
* `hammerspace_dsx_ebs_count`: Number of data EBS volumes per DSX instance (Default: `1`).
* `hammerspace_dsx_add_vols`: Add non-boot EBS volumes as Hammerspace storage (Default: `true`).

---

### ECGroup Variables

These variables configure the ECGroup storage cluster and are prefixed with `ecgroup_` in your `terraform.tfvars` file.

* `ecgroup_instance_type`: EC2 instance type for the cluster nodes.
* `ecgroup_node_count`: Number of EC2 nodes to create (must be between 4 and 16).
* `ecgroup_boot_volume_size`: Root volume size (GB) for each node.
* `ecgroup_boot_volume_type`: Root volume type for each node.
* `ecgroup_metadata_volume_size`: Size of the metadata EBS volume for each node in GiB.
* `ecgroup_metadata_volume_type`: Type of EBS metadata volume for each node.
* `ecgroup_metadata_volume_throughput`: Throughput for metadata EBS volumes.
* `ecgroup_metadata_volume_iops`: IOPS for the metadata EBS volumes.
* `ecgroup_storage_volume_count`: Number of storage volumes to attach to each node.
* `ecgroup_storage_volume_size`: Size of each EBS storage volume (GB).
* `ecgroup_storage_volume_type`: Type of EBS storage volume.
* `ecgroup_storage_volume_throughput`: Throughput for each EBS storage volume.
* `ecgroup_storage_volume_iops`: IOPS for each EBS storage volume.
* `ecgroup_user_data`: Path to user data script for the nodes.

---

### Ansible Variables

These variables configure the Ansible controller instance and its playbook. Prefixes are `ansible_` where applicable.

* `ansible_instance_count`: Number of Ansible instances (Default: `1`).
* `ansible_ami`: (Required) AMI for Ansible instances.
* `ansible_instance_type`: Instance type for Ansible (Default: `"m5n.8xlarge"`).
* `ansible_boot_volume_size`: Root volume size (GB) (Default: `100`).
* `ansible_boot_volume_type`: Root volume type (Default: `"gp2"`).
* `ansible_user_data`: Path to user data script for Ansible.
* `ansible_target_user`: Default system user for Ansible EC2 (Default: `"ubuntu"`).
* `volume_group_name`: The name of the volume group for Hammerspace storage, used by the Ansible playbook. (Default: `"vg-auto"`).
* `share_name`: (Required) The name of the share to be created on the storage, used by the Ansible playbook.

---

## Infrastructure Guardrails and Validation

To prevent common errors and ensure a smooth deployment, this project includes several "pre-flight" checks that run during the `terraform plan` phase. If any of these checks fail, the plan will stop with a clear error message before any resources are created.

* **Network Validation**:
    * **VPC and Subnet Existence**: Verifies that the `vpc_id` and `subnet_id` you provide correspond to real resources in the target AWS region.
    * **Subnet in VPC**: Confirms that the provided subnet is actually part of the specified VPC.

* **Resource Availability Validation**:
    * **Instance Type Availability**: Checks if your chosen EC2 instance types (e.g., `m5n.8xlarge`) are offered by AWS in the specific Availability Zone of your subnet.
    * **AMI Existence**: Verifies that the AMI IDs you provide for clients, storage, Hammerspace, and Ansible are valid and accessible in the target region. This check supports both public AMIs and private/partner AMIs (via the `custom_ami_owner_ids` variable).

* **Capacity and Provisioning Guardrails**:
    * **On-Demand Capacity Reservations**: Before attempting to create instances, Terraform will first try to reserve the necessary capacity. If AWS cannot fulfill the reservation due to a real-time capacity shortage, the `terraform apply` will fail quickly instead of hanging.
    * **Destruction Safety**: The standalone Anvil instance is protected by a `lifecycle` block to prevent accidental deletion. You must explicitly set `sa_anvil_destruction = true` to destroy it.

---

## Dealing with AWS Capacity and Timeouts

When deploying large or specialized EC2 instances, you may encounter `InsufficientInstanceCapacity` errors from AWS. This project includes several advanced features to manage this issue and provide predictable behavior.

### Controlling API Retries (`max_retries`)

The AWS provider will automatically retry certain API errors, such as `InsufficientInstanceCapacity`. While normally helpful, this can cause the `terraform apply` command to hang for many minutes before finally failing.

To get immediate feedback, you can instruct the provider not to retry. In your root `main.tf` (or an override file like `local_override.tf`), configure the `provider` block:

```terraform
provider "aws" {
  region      = var.region
  
  # Fail immediately on the first retryable error instead of hanging.
  # Set to 0 for debugging, or a small number like 2 for production.
  max_retries = 0
}
```
Setting `max_retries = 0` is excellent for debugging capacity issues, as it ensures the `apply` fails on the very first error.

### Controlling Capacity Timeouts

To prevent long hangs, this project first creates On-Demand Capacity Reservations to secure hardware before launching instances. You can control how long Terraform waits for these reservations to be fulfilled using a variable in your `.tfvars` file:

* **`capacity_reservation_create_timeout`**: Sets the timeout for creating capacity reservations. If AWS cannot find the hardware within this period, the `apply` will fail. (Default: `"5m"`)

### Understanding the Timeout Behavior

It is critical to understand how these settings interact. Even with `max_retries = 0`, you may see Terraform wait for the full duration of the `capacity_reservation_create_timeout`.

This is not a bug; it is the fundamental behavior of the AWS Capacity Reservation system:
1.  Terraform sends the request to AWS to create the reservation.
2.  AWS acknowledges the request and places the reservation in a **`pending`** state. The API call itself succeeds, so `max_retries` has no effect.
3.  AWS now searches for physical hardware to fulfill your request in the background.
4.  The Terraform provider enters a "waiter" loop, polling AWS every ~15 seconds, asking, "Is the reservation `active` yet?"
5.  The `Still creating...` message you see during `terraform apply` corresponds to this waiting period.

The `capacity_reservation_create_timeout` you set applies to this **entire waiting period**. If the reservation does not become `active` within that time (e.g., `"5m"`), Terraform will stop waiting and fail the `apply`. The timeout is working correctly by putting a boundary on the wait, but it will not cause an *instant* failure if the capacity isn't immediately available.

### Important Warning on Capacity Reservation Billing

> **Warning:** On-Demand Capacity Reservations begin to incur charges at the standard On-Demand rate as soon as they are successfully created, **whether you are running an instance in them or not.**
>
> In order to avoid unnecessary charges, Capacity Reservations will automatically expire 10 minutes after creation. The sole purpose of the Capacity Reservation is to make sure that resources
> are available so that Terraform doesn't hang during the `terraform apply` because those resources are unavailable in your availability zone. 

---

## Required IAM Permissions for Custom Instance Profile
If you are using the `hammerspace_profile_id` variable to provide a pre-existing IAM Instance Profile, the associated IAM Role must have a policy attached with the following permissions.

**Summary for AWS Administrators:**
1.  Create an IAM Policy with the JSON below.
2.  Create an IAM Role for the EC2 Service (`ec2.amazonaws.com`).
3.  Attach the new policy to the role.
4.  Create an Instance Profile and attach the role to it.
5.  Provide the name of the **Instance Profile** to the user running Terraform.

**Required IAM Policy JSON:**
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

**Permission Breakdown:**
* **SSHKeyAccess**: Allows the instance to fetch SSH public keys from IAM for user access, if `iam_user_access` is enabled.
* **HAInstanceDiscovery**: Allows the Anvil HA nodes to discover each other's state and tags.
* **HAFloatingIP**: **(Crucial for HA)** Allows an Anvil node to take over the floating cluster IP address from its partner during a failover.
* **MarketplaceMetering**: Required for instances launched from the AWS Marketplace to report usage for billing.

---

## Securely Accessing Instances

For production or security-conscious environments, allowing ingress traffic from the entire internet (`0.0.0.0/0`) is not recommended. This project defaults to a more secure model. Ingress traffic is only allowed from two sources:
1.  The CIDR block of the VPC itself, allowing all instances within the deployment to communicate with each other.
2.  Any additional CIDR blocks you specify in the `allowed_source_cidr_blocks` variable, which is ideal for corporate VPNs or management networks.

### Option 1: Bastion Host (Recommended for Production)

A Bastion Host (or "jump box") is a single, hardened EC2 instance that lives in a public subnet and is the only instance that accepts connections from the internet (or a corporate VPN). Users first SSH into the bastion host, and from there, they can "jump" to other instances in private subnets using their private IP addresses.

This project supports this pattern through the `allowed_ssh_source_security_group_ids` variable in the `storage_servers` module (and can be added to others). You would:
1.  Create a security group for your bastion host.
2.  Pass the ID of that security group to the module.
3.  The module will then create an ingress rule allowing SSH traffic *only* from resources within that bastion host security group.

### Option 2: AWS Systems Manager Session Manager (Most Secure)

A more modern approach is to use AWS Systems Manager Session Manager. This service allows you to get a secure shell connection to your instances without opening **any** inbound ports (not even port 22). Access is controlled entirely through IAM policies, providing the highest level of security and auditability. This requires setting up the SSM Agent on your instances and configuring the appropriate IAM permissions.

---

## Production Backend

A `backend.tf` file defines **where Terraform stores its state.**. For production environments, it is best practice to use a **remote backend like Amazon S3 with DynamoDB for state locking**--ensuring collaboration and preventing corruption.

***Example `backend.tf` for AWS (S3 + DynamoDB)
```
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

## Prerequisites

Before running this Terraform configuration, please ensure the following one-time setup tasks are complete for the target AWS account.

* **Install Tools**: You must have [Terraform](https://developer.hashicorp.com/terraform/downloads) and the [AWS CLI](https://aws.amazon.com/cli/) installed and configured on your local machine.
* **AWS Marketplace Subscription**: This configuration uses partner AMIs (e.g., for Hammerspace) which require a subscription in the AWS Marketplace. If you encounter an `OptInRequired` error during `terraform apply`, the error message will contain a specific URL. You must visit this URL, sign in to your AWS account, and accept the terms to subscribe to the product. This only needs to be done once per AWS account for each product.

---

## How to Use

1.  **Initialize**: `terraform init`
2.  **Configure**: Create a `terraform.tfvars` file to set your desired variables. At a minimum, you must provide `project_name`, `vpc_id`, `subnet_id`, `key_name`, and the required `*_ami` variables.
3.  **Plan**: `terraform plan`
4.  **Apply**: `terraform apply`

### Local Development Setup (AWS Profile)
To use a named profile from your `~/.aws/credentials` file for local runs without affecting the CI/CD pipeline, you should use a local override file. This prevents your personal credentials profile from being committed to source control.

1.  **Create an override file**: In the root directory of the project, create a new file named `local_override.tf`.
2.  **Add the provider configuration**: Place the following code inside `local_override.tf`, replacing `"your-profile-name"` with your actual profile name.

    ```terraform
    # Terraform-AWS/local_override.tf
    # This file is for local development overrides and should not be committed.

    provider "aws" {
      profile = "your-profile-name"
    }
    ```
When you run Terraform locally, it will automatically merge this file with `main.tf`, using your profile. The CI/CD system will not have this file and will correctly fall back to using the credentials stored in its environment secrets.

---

## Important Note on Placement Group Deletion

When you run `terraform destroy` on a configuration that created a placement group, you may see an error like this:

`Error: InvalidPlacementGroup.InUse: The placement group ... is in use and may not be deleted.`

This is normal and expected behavior due to a race condition in the AWS API. It happens because Terraform sends the requests to terminate the EC2 instances and delete the placement group at nearly the same time. If the instances haven't fully terminated on the AWS backend, the API will reject the request to delete the group.

**The solution is to simply run `terraform destroy` a second time.** The first run will successfully terminate the instances, and the second run will then be able to successfully delete the now-empty placement group.

---

## Outputs

After a successful `apply`, Terraform will provide the following outputs. Sensitive values will be redacted and can be viewed with `terraform output <output_name>`.

* `client_instances`: A list of non-sensitive details for each client instance (ID, IP, Name).
* `storage_instances`: A list of non-sensitive details for each storage instance.
* `hammerspace_anvil`: **(Sensitive)** A list of detailed information for the deployed Anvil nodes.
* `hammerspace_dsx`: **(Sensitive)** A list of detailed information for the deployed DSX nodes.
* `hammerspace_dsx_private_ips`: A list of private IP addresses for the Hammerspace DSX instances.
* `hammerspace_mgmt_url`: The URL to access the Hammerspace management interface.
* `ecgroup_nodes`: Details about the deployed ECGroup nodes.
* `ansible_details`: Details for the deployed Ansible controller.

---
## Modules

This project is structured into the following modules:
* **clients**: Deploys client EC2 instances.
* **storage_servers**: Deploys storage server EC2 instances with configurable RAID and NFS exports.
* **hammerspace**: Deploys Hammerspace Anvil (metadata) and DSX (data) nodes.
* **ecgroup**: Deploys a storage cluster that combines all of its storage into an erasure-coded array.
* **ansible**: Deploys an Ansible controller instance which performs "Day 2" configuration tasks after the primary infrastructure is provisioned. Its key functions are:
    * **Hammerspace Integration**: It runs a playbook that connects to the Anvil's API to add the newly created storage servers as data nodes, create a volume group, and create a share.
    * **ECGroup Configuration**: It runs a playbook to configure the ECGroup cluster, create the array, and set up the necessary services.
    * **Passwordless SSH Setup**: It runs a second playbook that orchestrates a key exchange between all client and storage nodes, allowing them to SSH to each other without passwords for automated scripting.
