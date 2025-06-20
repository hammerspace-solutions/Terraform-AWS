# Global variables (NO prefix)

variable "region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-west-2"
}

variable "availability_zone" {
  description = "AWS availability zone"
  type        = string
  default     = "us-west-2b"
}

variable "vpc_id" {
  description = "VPC ID for all resources"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for resources"
  type        = string
}

variable "key_name" {
  description = "SSH key pair name"
  type        = string
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}

variable "project_name" {
  description = "Project name for tagging and resource naming"
  type        = string
  default     = ""
  validation {
    condition     = var.project_name != ""
    error_message = "Project must have a name"
  }
}

variable "ssh_keys_dir" {
  description = "Directory containing SSH public keys"
  type        = string
  default     = "./ssh_keys"
}

variable "deploy_components" {
  description = "Components to deploy. Valid values in the list are: \"all\", \"clients\", \"storage\", \"hammerspace\"."
  type        = list(string)
  default     = ["all"]
  validation {
    condition = alltrue([
      for c in var.deploy_components : contains(["all", "clients", "storage", "hammerspace"], c)
    ])
    error_message = "Each item in deploy_components must be one of: \"all\", \"clients\", \"storage\", or \"hammerspace\"."
  }
}

# CLIENT-SPECIFIC VARIABLES (WITH clients_ PREFIX)
variable "clients_instance_count" {
  description = "Number of client instances"
  type        = number
  default     = 1
}

variable "clients_ami" {
  description = "AMI for client instances"
  type        = string
}

variable "clients_instance_type" {
  description = "Instance type for clients"
  type        = string
  default     = "m5n.8xlarge"
}

variable "clients_boot_volume_size" {
  description = "Root volume size (GB) for clients"
  type        = number
  default     = 100
}

variable "clients_boot_volume_type" {
  description = "Root volume type for clients"
  type        = string
  default     = "gp2"
}

variable "clients_ebs_count" {
  description = "Number of extra EBS volumes per client"
  type        = number
  default     = 1
}

variable "clients_ebs_size" {
  description = "Size of each EBS volume (GB) for clients"
  type        = number
  default     = 1000
}

variable "clients_ebs_type" {
  description = "Type of EBS volume for clients"
  type        = string
  default     = "gp3"
}

variable "clients_ebs_throughput" {
  description = "Throughput for gp3 EBS volumes for clients (MB/s)"
  type        = number
  default     = null
}

variable "clients_ebs_iops" {
  description = "IOPS for gp3/io1/io2 EBS volumes for clients"
  type        = number
  default     = null
}

variable "clients_user_data" {
  description = "Path to user data script for clients"
  type        = string
  default     = ""
}

variable "clients_target_user" {
  description = "Default system user for client EC2s"
  type        = string
  default     = "ubuntu"
}

# STORAGE-SPECIFIC VARIABLES (WITH storage_ PREFIX)
variable "storage_instance_count" {
  description = "Number of storage instances"
  type        = number
  default     = 1
}

variable "storage_ami" {
  description = "AMI for storage instances"
  type        = string
}

variable "storage_instance_type" {
  description = "Instance type for storage"
  type        = string
  default     = "m5n.8xlarge"
}

variable "storage_boot_volume_size" {
  description = "Root volume size (GB) for storage"
  type        = number
  default     = 100
}

variable "storage_boot_volume_type" {
  description = "Root volume type for storage"
  type        = string
  default     = "gp2"
}

variable "storage_ebs_count" {
  description = "Number of extra EBS volumes per storage"
  type        = number
  default     = 1
}

variable "storage_ebs_size" {
  description = "Size of each EBS volume (GB) for storage"
  type        = number
  default     = 1000
}

variable "storage_ebs_type" {
  description = "Type of EBS volume for storage"
  type        = string
  default     = "gp3"
}

variable "storage_ebs_throughput" {
  description = "Throughput for gp3 EBS volumes for storage (MB/s)"
  type        = number
  default     = null
}

variable "storage_ebs_iops" {
  description = "IOPS for gp3/io1/io2 EBS volumes for storage"
  type        = number
  default     = null
}

variable "storage_user_data" {
  description = "Path to user data script for storage"
  type        = string
  default     = ""
}

variable "storage_target_user" {
  description = "Default system user for storage EC2s"
  type        = string
  default     = "ubuntu"
}

variable "storage_raid_level" {
  description = "RAID level to configure (raid-0, raid-5, or raid-6)"
  type        = string
  default     = "raid-5"

  validation {
    condition     = contains(["raid-0", "raid-5", "raid-6"], var.storage_raid_level)
    error_message = "RAID level must be one of: raid-0, raid-5, or raid-6"
  }
}

# Hammerspace-specific variables
variable "hammerspace_ami" {
  description = "AMI ID for Hammerspace instances"
  type        = string
  default     = "ami-04add4f19d296b3e7"
}

variable "hammerspace_iam_admin_group_id" {
  description = "IAM admin group ID for SSH access (can be existing group name or blank to create new)"
  type        = string
  default     = ""
}

variable "hammerspace_profile_id" {
  description = "The name of an existing IAM Instance Profile to attach to Hammerspace instances. If left blank, a new one will be created with the necessary policies."
  type        = string
  default     = ""
}

variable "hammerspace_anvil_security_group_id" {
  description = "Optional: An existing security group ID to use for the Anvil nodes."
  type        = string
  default     = ""
}

variable "hammerspace_dsx_security_group_id" {
  description = "Optional: An existing security group ID to use for the DSX nodes."
  type        = string
  default     = ""
}

variable "hammerspace_anvil_count" {
  description = "Number of Anvil instances to deploy (0=none, 1=standalone, 2=HA)"
  type        = number
  default     = 0
  validation {
    condition     = var.hammerspace_anvil_count >= 0 && var.hammerspace_anvil_count <= 2
    error_message = "anvil count must be 0, 1 (standalone), or 2 (HA)"
  }
}

variable "hammerspace_sa_anvil_destruction" {
  description = "A safety switch to allow the destruction of a standalone Anvil. Must be set to true for 'terraform destroy' to succeed on a 1-Anvil deployment."
  type        = bool
  default     = false
}

variable "hammerspace_anvil_instance_type" {
  description = "Instance type for Anvil metadata server"
  type        = string
  default     = "m5zn.12xlarge"
}

variable "hammerspace_dsx_instance_type" {
  description = "Instance type for DSX nodes"
  type        = string
  default     = "m5.xlarge"
}

variable "hammerspace_dsx_count" {
  description = "Number of DSX instances"
  type        = number
  default     = 1
}

variable "hammerspace_anvil_meta_disk_size" {
  description = "Metadata disk size in GB for Anvil"
  type        = number
  default     = 1000
}

variable "hammerspace_anvil_meta_disk_type" {
  description = "Type of EBS volume for Anvil metadata disk (e.g., gp3, io2)"
  type        = string
  default     = "gp3"
}

variable "hammerspace_anvil_meta_disk_throughput" {
  description = "Throughput for gp3 EBS volumes for the Anvil metadata disk (MiB/s)"
  type        = number
  default     = null
}

variable "hammerspace_anvil_meta_disk_iops" {
  description = "IOPS for gp3/io1/io2 EBS volumes for the Anvil metadata disk"
  type        = number
  default     = null
}

variable "hammerspace_dsx_ebs_size" {
  description = "Size of each EBS Data volume per DSX node in GB"
  type        = number
  default     = 200
}

variable "hammerspace_dsx_ebs_type" {
  description = "Type of each EBS Data volume for DSX (e.g., gp3, io2)"
  type        = string
  default     = "gp3"
}

variable "hammerspace_dsx_ebs_iops" {
  description = "IOPS for each EBS Data volume for DSX"
  type        = number
  default     = null
}

variable "hammerspace_dsx_ebs_throughput" {
  description = "Throughput for each EBS Data volume for DSX (MiB/s)"
  type        = number
  default     = null
}

variable "hammerspace_dsx_ebs_count" {
  description = "Number of data EBS volumes to attach to each DSX instance."
  type        = number
  default     = 1
}

variable "hammerspace_dsx_add_vols" {
  description = "Add non-boot EBS volumes as Hammerspace storage volumes"
  type        = bool
  default     = true
}

variable "placement_group_name" {
  description = "Optional: The name of the placement group to create and launch instances into. If left blank, no placement group is used."
  type        = string
  default     = ""
}

variable "placement_group_strategy" {
  description = "The strategy to use for the placement group: cluster, spread, or partition."
  type        = string
  default     = "cluster"
  validation {
    condition     = contains(["cluster", "spread", "partition"], var.placement_group_strategy)
    error_message = "Allowed values for placement_group_strategy are: cluster, spread, or partition."
  }
}
