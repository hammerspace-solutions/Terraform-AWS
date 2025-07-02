# Terraform-AWS
This project uses Terraform to provision resources on AWS. The deployment is modular, allowing you to deploy client machines, storage servers, and a Hammerspace environment either together or independently.

This project was originally written for internal Hammerspace use to size Hammerspace resources within AWS for inclusion in a LLM model for automated AI sizing. It has since expanded to allow customers to deploy linux clients, linux storage servers, and Hammerspace Anvil's and DSX's for any use that they wish.

Guard-rails have been added to make sure that the deployments are as easy as possible for the uninitiated cloud user.

## Table of Contents
- [Configuration](#configuration)
  - [Global Variables](#global-variables)
- [Component Variables](#component-variables)
  - [Client Variables](#client-variables)
  - [Storage Server Variables](#storage-server-variables)
  - [Hammerspace Variables](#hammerspace-variables)
  - [Ansible Variables](#ansible-variables)
- [Dealing with AWS Capacity and Timeouts](#dealing-with-aws-capacity-and-timeouts)
  - [Controlling API Retries (`max_retries`)](#controlling-api-retries-max_retries)
  - [Controlling Capacity Timeouts](#controlling-capacity-timeouts)
  - [Understanding the Timeout Behavior](#understanding-the-timeout-behavior)
- [Required IAM Permissions for Custom Instance Profile](#required-iam-permissions-for-custom-instance-profile)
- [Prerequisites](#prerequisites)
- [How to Use](#how-to-use)
  - [Local Development Setup (AWS Profile)](#local-development-setup-aws-profile)
- [Important Note on Placement Group Deletion](#important-note-on-placement-group-deletion)
- [Outputs](#outputs)
- [Modules](#modules)


## Configuration

Configuration is managed through `terraform.tfvars` by setting values for the variables defined in `variables.tf`.

### Global Variables

These variables apply to the overall deployment:

* `region`: AWS region for all resources (Default: "us-west-2").
* `assign_public_ip`: If `true`, assigns a public IP address to all created EC2 instances. If `false`, only a private IP will be assigned. (Default: `false`).
* `availability_zone`: AWS availability zone for resource placement (Default: "us-west-2b").
* `vpc_id`: (Required) VPC ID for all resources.
* `subnet_id`: (Required) Subnet ID for resources.
* `key_name`: (Required) SSH key pair name for instance access.
* `tags`: Common tags to apply to all resources (Default: `{}`).
* `project_name`: (Required) Project name used for tagging and resource naming.
* `ssh_keys_dir`: A local directory for public SSH key files (`.pub`). The startup script automatically adds these keys to the `authorized_keys` file on all servers. (Default: `"./ssh_keys"`).
* `deploy_components`: List of components to deploy (e.g., `["clients", "storage"]` or `["all"]`) (Default: `["all"]`).
* `placement_group_name`: (Optional) The name of the placement group to create and launch instances into.
* `placement_group_strategy`: The strategy for the placement group: `cluster`, `spread`, or `partition` (Default: `cluster`).
* `capacity_reservation_create_timeout`: The maximum time to wait for a capacity reservation to be fulfilled before failing (e.g., `"5m"`). (Default: `"5m"`).

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
* `client_ebs_volumes`: **(Sensitive)** A list of sensitive EBS volume details for each client.
* `storage_instances`: A list of non-sensitive details for each storage instance.
* `storage_ebs_volumes`: **(Sensitive)** A list of sensitive EBS volume details for each storage server.
* `hammerspace_anvil`: **(Sensitive)** A list of detailed information for the deployed Anvil nodes.
* `hammerspace_dsx`: **(Sensitive)** A list of detailed information for the deployed DSX nodes.
* `hammerspace_dsx_private_ips`: A list of private IP addresses for the Hammerspace DSX instances.
* `hammerspace_mgmt_url`: The URL to access the Hammerspace management interface.

---
## Modules

This project is structured into the following modules:
* **clients**: Deploys client EC2 instances.
* **storage_servers**: Deploys storage server EC2 instances with configurable RAID and NFS exports.
* **hammerspace**: Deploys Hammerspace Anvil (metadata) and DSX (data) nodes.
* **ansible**: Deploys an Ansible controller instance which performs "Day 2" configuration tasks after the primary infrastructure is provisioned. Its key functions are:
    * **Hammerspace Integration**: It runs a playbook that connects to the Anvil's API to add the newly created storage servers as data nodes, create a volume group, and create a share.
    * **Passwordless SSH Setup**: It runs a second playbook that orchestrates a key exchange between all client and storage nodes, allowing them to SSH to each other without passwords for automated scripting.
