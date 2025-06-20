# Client-specific variables

variable "instance_count" {
  description = "Number of client instances"
  type        = number
}

variable "ami" {
  description = "AMI for client instances"
  type        = string
}

variable "instance_type" {
  description = "Instance type for clients"
  type        = string
}

variable "boot_volume_size" {
  description = "Root volume size (GB) for clients"
  type        = number
}

variable "boot_volume_type" {
  description = "Root volume type for clients"
  type        = string
}

variable "ebs_count" {
  description = "Number of extra EBS volumes per client"
  type        = number
}

variable "ebs_size" {
  description = "Size of each EBS volume (GB) for clients"
  type        = number
}

variable "ebs_type" {
  description = "Type of EBS volume for clients"
  type        = string
}

variable "ebs_throughput" {
  description = "Throughput for gp3 EBS volumes for clients (MB/s)"
  type        = number
  default     = null
}

variable "ebs_iops" {
  description = "IOPS for gp3/io1/io2 EBS volumes for clients"
  type        = number
  default     = null
}

variable "user_data" {
  description = "Path to user data script for clients"
  type        = string
}

variable "target_user" {
  description = "Default system user for client EC2s"
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

