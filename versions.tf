terraform {
  required_version = ">= 1.1.11"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.3.0"
    }
  }
}
