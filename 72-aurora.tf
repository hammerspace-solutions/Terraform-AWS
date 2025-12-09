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
# 72-aurora.tf
#
# This file defines all the variables for the creation and maintenance of
# the Aurora Database for Project Houston
# -----------------------------------------------------------------------------

variable "aurora_engine" {
  description = "Aurora engine (aurora-postgresql or aurora-mysql)"
  type        = string
  default     = "aurora-postgresql"
}

variable "aurora_engine_version" {
  description = "Aurora engine version. If empty, AWS chooses a suitable default."
  type        = string
  default     = ""
}

variable "aurora_instance_class" {
  description = "Aurora instance class (e.g., db.r6g.large)"
  type        = string
  default     = "db.r6g.large"
}

variable "aurora_instance_count" {
  description = "Number of Aurora instances in the cluster"
  type        = number
  default     = 2
}

variable "aurora_db_name" {
  description = "Initial database name within the Aurora cluster"
  type        = string
  default     = "projecthouston"
}

variable "aurora_master_username" {
  description = "Master username for the Aurora cluster"
  type        = string
}

variable "aurora_master_password" {
  description = "Master password for the Aurora cluster"
  type        = string
  sensitive   = true
}

variable "aurora_backup_retention_days" {
  description = "Number of days to retain Aurora automated backups"
  type        = number
  default     = 7
}

variable "aurora_preferred_backup_window" {
  description = "Preferred backup window (UTC), e.g. 04:00-05:00"
  type        = string
  default     = "04:00-05:00"
}

variable "aurora_preferred_maintenance_window" {
  description = "Preferred maintenance window (UTC), e.g. sun:06:00-sun:07:00"
  type        = string
  default     = "sun:06:00-sun:07:00"
}

variable "aurora_deletion_protection" {
  description = "Enable deletion protection for the Aurora cluster"
  type        = bool
  default     = true
}

variable "aurora_storage_encrypted" {
  description = "Encrypt Aurora storage"
  type        = bool
  default     = true
}

variable "aurora_kms_key_id" {
  description = "KMS key ID/ARN for Aurora storage encryption (optional)"
  type        = string
  default     = ""
}

variable "aurora_enable_performance_insights" {
  description = "Enable Performance Insights on Aurora instances"
  type        = bool
  default     = true
}

variable "aurora_performance_insights_retention_period" {
  description = "Performance Insights retention in days (7, 731, 1095, etc.)"
  type        = number
  default     = 7
}

variable "aurora_performance_insights_kms_key_id" {
  description = "KMS key ID/ARN for Performance Insights (optional)"
  type        = string
  default     = ""
}

variable "aurora_enable_http_endpoint" {
  description = "Enable the API so that someone can talk to the Aurora DB"
  type	      = bool
  default     = false
}

variable "aurora_skip_final_snapshot" {
  description = "Whether to skip the final snapshot when destroying the Aurora cluster."
  type        = bool
  default     = true
}

variable "aurora_final_snapshot_identifier" {
  description = "Final snapshot identifier for Aurora when aurora_skip_final_snapshot is false."
  type        = string
  default     = ""
}

variable "aurora_event_email" {
  description = "Email address to receive Aurora/RDS event notifications."
  type	      = string
  default     = ""
}
