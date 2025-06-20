# Ansible specific variables

variable "instance_count" {
  description = "Number of Ansible instances"
  type        = number
}

variable "ami" {
  description = "AMI for Ansible instances"
  type        = string
}

variable "instance_type" {
  description = "Instance type for Ansible"
  type        = string
}

variable "boot_volume_size" {
  description = "Root volume size (GB) for Ansible"
  type        = number
}

variable "boot_volume_type" {
  description = "Root volume type for Ansible"
  type        = string
}


variable "user_data" {
  description = "Path to user data script for Ansible"
  type        = string
}

variable "target_user" {
  description = "Default system user for Ansible EC2"
  type        = string
}

# Global variables passed-through

variable "region" {
  description = "AWS region"
  type        = string
}

variable "availability_zone" {
  description = "AWS availability zone"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID"
  type        = string
}

variable "key_name" {
  description = "SSH key pair name"
  type        = string
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
}

variable "project_name" {
  description = "Project name for tagging and resource naming"
  type        = string
}

variable "ssh_keys_dir" {
  description = "Directory containing SSH public keys"
  type        = string
}

variable "placement_group_name" {
  description = "Optional: The name of the placement group for the instances."
  type        = string
  default     = ""
}

variable "mgmt_ip" {
  description = "Hammerspace management IP address"
  type        = list(string)
}

variable "anvil_instances" {
  description = "Anvil instances details"
  type        = list(object({
    type      = string
    id        = string
    arn       = string
    private_ip = string
    public_ip = string
    key_name  = string
    iam_profile = string
    placement_group = string
    all_private_ips_on_eni_set = set(string)
    floating_ip_candidate = string
  }))
}

variable "storage_instances" {
  description = "Storage instances details"
  type        = list(object({
    id        = string
    private_ip= string
    name      = string
  }))
}


variable "volume_group_name" {
  description = "Volume group name for Anvil"
  type        = string
  default     = "vg-auto"
}

variable "share_name" {
  description = "Share name for Anvil"
  type        = string
}

