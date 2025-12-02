# Copyright (c) 2025 Hammerspace, Inc
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# -----------------------------------------------------------------------------
# variables.tf
#
# This file defines all the variables for the creation and maintenance of
# Amazon MQ in AWS for Project Houston
# -----------------------------------------------------------------------------

# variables.tf - Define variables for customization

variable "vpc_cidr" {
  description = "VPC CIDR Block"
  type        = string
  default     = ""
}

variable "private_subnet_a_cidr" {
  description = "Private Subnet-A CIDR Block"
  type        = string
  default     = ""
}

variable "subnet_a_az" {
  description = "Subnet-A Availability Zone"
  type        = string
  default     = ""
}

variable "private_subnet_b_cidr" {
  description = "Private Subnet-B CIDR Block"
  type        = string
  default     = ""
}

variable "subnet_b_az" {
  description = "Subnet-B Availability Zone"
  type        = string
  default     = ""
}

variable "public_subnet_a_cidr" {
  description = "Public Subnet-A CIDR"
  type	      = string
  default     = ""
}

variable "public_subnet_b_cidr" {
  description = "Public Subnet-B CIDR"
  type	      = string
  default     = ""
}

variable "hosted_zone_name" {
  description = "Route 53 Private Hosted Zone Name"
  type        = string
  default     = ""
}

# RabbitMQ (Amazon MQ) settings

variable "rabbitmq_engine_version" {
  description = "RabbitMQ engine version for Amazon MQ"
  type        = string
  # Check AWS docs/console for latest supported; 3.13 as an example
  default     = "3.13"
}

variable "rabbitmq_instance_type" {
  description = "Amazon MQ RabbitMQ broker instance type"
  type        = string
  # mq.m5 family is typical for RabbitMQ
  default     = "mq.m5.large"
}

variable "rabbitmq_admin_username" {
  description = "Initial admin username for Amazon MQ RabbitMQ"
  type        = string
  sensitive   = true
}

variable "rabbitmq_admin_password" {
  description = "Initial admin password for Amazon MQ RabbitMQ"
  type        = string
  sensitive   = true
}

variable "site_admin_username" {
  description = "Admin username for the administration user on the *site* RabbitMQ containers"
  type        = string
  sensitive   = true
}

variable "site_admin_password" {
  description = "Password for the admin user on the *site* RabbitMQ containers"
  type        = string
  sensitive   = true
}

variable "site_admin_password_hash" {
  description = "Precomputed RabbitMQ password hash for the site admin user (for definitions.json)"
  type        = string
  sensitive   = true
}
