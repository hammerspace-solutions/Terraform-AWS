# SizingTerraform
Terraform templates to create clients, storage, and Hammerspace for AWS sizing.

This project uses Terraform to provision resources on AWS. The deployment is modular, allowing you to deploy client machines, storage servers, and a Hammerspace environment either together or independently.

## Table of Contents
- [Configuration](#configuration)
  - [Global Variables](#global-variables)
- [Component Variables](#component-variables)
  - [Client Variables](#client-variables)
  - [Storage Server Variables](#storage-server-variables)
  - [Hammerspace Variables](#hammerspace-variables)
- [Required IAM Permissions for Custom Instance Profile](#required-iam-permissions-for-custom-instance-profile)
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
* `availability_zone`: AWS availability zone for resource placement (Default: "us-west-2b").
* `vpc_id`: (Required) VPC ID for all resources.
* `subnet_id`: (Required) Subnet ID for resources.
* `key_name`: (Required) SSH key pair name for instance access. This key is still required by AWS for the instance launch, even if not used for login.
* `tags`: Common tags to apply to all resources (Default: `{}`).
* `project_name`: (Required) Project name used for tagging and resource naming.
* `ssh_keys_dir`: A local directory where you can place multiple public SSH key files (e.g., `user1.pub`, `user2.pub`). The startup script will automatically add these keys to the `authorized_keys` file on all servers. This allows users to `ssh` into the instances with their own personal private keys instead of sharing the single EC2 `.pem` file. (Default: `"./ssh_keys"`).
* `deploy_components`: List of components to deploy (e.g., `["clients", "storage", "hammerspace"]` or `["all"]`) (Default: `["all"]`).
* `placement_group_name`: (Optional) The name of the placement group to create and launch instances into. If left blank, no placement group is used.
* `placement_group_strategy`: The strategy for the placement group: `cluster`, `spread`, or `partition` (Default: `cluster`).

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
* **`hammerspace_anvil_security_group_id`**: (Optional) The ID of a pre-existing security group to attach to the Anvil nodes. If left blank, the module will create and configure a new security group. This is useful for debugging or integrating with existing network rules.
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

## Required IAM Permissions for Custom Instance Profile
If you are using the `hammerspace_profile_id` variable to provide a pre-existing IAM Instance Profile, the associated IAM Role must have a policy attached with the following permissions.

**Summary for AWS Administrators:**
1.  Create an IAM Policy with the JSON below.
2.  Create an IAM Role for the EC2 Service (`ec2.amazonaws.com`).
3.  Attach the new policy to the role.
4.  Create an Instance Profile and attach the role to it.
5.  Provide the name of the **Instance Profile** to the user running Terraform.

**Required IAM Policy JSON:**
```
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

## How to Use

1.  **Prerequisites**:
    * Install Terraform.
    * Install and configure the AWS CLI. Your credentials should be stored in `~/.aws/credentials`.
2.  **Configure Local AWS Profile**: If you use a named profile from your `~/.aws/credentials` file for local development, follow the setup in the section below. Otherwise, Terraform will use environment variables.
3.  **Initialize**: `terraform init`
4.  **Configure**: Create a `terraform.tfvars` file to set your desired variables. At a minimum, you must provide `project_name`, `vpc_id`, `subnet_id`, `key_name`, and the required `*_ami` variables.
5.  **Plan**: `terraform plan`
6.  **Apply**: `terraform apply`

### Local Development Setup (AWS Profile)
To use a named profile from your `~/.aws/credentials` file for local runs without affecting the CI/CD pipeline, you should use a local override file. This prevents your personal credentials profile from being committed to source control.

1.  **Create an override file**: In the root directory of the project, create a new file named `local_override.tf`.
2.  **Add the provider configuration**: Place the following code inside `local_override.tf`, replacing `"your-profile-name"` with your actual profile name.

    ```terraform
    # SizingTerraform/local_override.tf
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
