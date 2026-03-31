terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.9" 
    }
  }
}

# The actual API connection is defined in the root, not the module
provider "aws" {
  region = "us-east-1"
}