# Prefixless variables for internal module use
variable "common_config" {
  description = "A map containing common configuration values like region, VPC, subnet, etc."
  type = object({
    region               = string
    availability_zone    = string
    vpc_id               = string
    subnet_id            = string
    key_name             = string
    tags                 = map(string)
    project_name         = string
    assign_public_ip     = bool
    ssh_keys_dir         = string
    placement_group_name = string
  })
}

variable "capacity_reservation_id" {
  description = "The ID of the On-Demand Capacity Reservation to target."
  type        = string
  default     = null
}

variable "placement_group_name" {
  description = "Optional: The name of the placement group for the instances."
  type        = string
  default     = ""
}

# ECGroup specific variables
variable "instance_type" {
  description = "Instance type for ecgroup node"
  type        = string
}

variable "node_count" {
  description = "Number of ecgroup node instances"
  type        = number
}

variable "ami" {
  description = "AMI for ecgroup instances"
  type        = string
}

variable "boot_volume_size" {
  description = "Root volume size (GB) for ecgroup nodes"
  type        = number
}

variable "boot_volume_type" {
  description = "Root volume type for ecgroup nodes"
  type        = string
}

variable "metadata_ebs_size" {
  description = "Size of the EBS metadata volume (GB) for ecgroup nodes"
  type        = number
}

variable "metadata_ebs_type" {
  description = "Type of EBS metadata volume for ecgroup nodes"
  type        = string
}

variable "metadata_ebs_throughput" {
  description = "Throughput for metadata EBS volumes for ecgroup nodes (MB/s)"
  type        = number
  default     = null
}

variable "metadata_ebs_iops" {
  description = "IOPS for gp3/io1/io2 the metadata EBS volumes for ecgroup nodes"
  type        = number
  default     = null
}

variable "storage_ebs_count" {
  description = "Number of extra EBS volumes per ecgroup nodes"
  type        = number
}

variable "storage_ebs_size" {
  description = "Size of each EBS storage volume (GB) for ecgroup nodes"
  type        = number
}

variable "storage_ebs_type" {
  description = "Type of EBS storage volume for ecgroup nodes"
  type        = string
}

variable "storage_ebs_throughput" {
  description = "Throughput for each EBS storage volumes for ecgroup nodes (MB/s)"
  type        = number
  default     = null
}

variable "storage_ebs_iops" {
  description = "IOPS for gp3/io1/io2 each EBS storage volumes for ecgroup nodes"
  type        = number
  default     = null
}

variable "user_data" {
  description = "Path to user data script for ECGroup nodes"
  type        = string
}