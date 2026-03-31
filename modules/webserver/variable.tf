variable "cluster_name" {
  description = "The name to use for all cluster resources (e.g., dev-app, prod-app)"
  type        = string
}

variable "environment" {
  description = "The deployment environment (e.g., dev, staging, prod)"
  type        = string
  
  # PRODUCTION FIX: Strict input validation
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be explicitly set to dev, staging, or prod."

    
  }
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC"
  type        = string
}

variable "public_subnet_cidr" {
  description = "The CIDR blocks and AZ indexes for public subnets"
  type = map(object({
    cidr_block = string
    az_index   = number
  }))
}

variable "private_subnet_cidr" {
  description = "The CIDR blocks and AZ indexes for private subnets"
  type = map(object({
    cidr_block = string
    az_index   = number
  }))
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string

  # PRODUCTION FIX: Restricting allowed instance families to prevent massive bills
  validation {
    condition     = can(regex("^t[23]\\.(micro|small|medium)$", var.instance_type))
    error_message = "Instance type must be a t2 or t3 micro, small, or medium."
  }
}

variable "asg_capacity" {
  description = "Capacity settings for the Auto Scaling Group"
  type = object({
    min     = number
    max     = number
    desired = number
  })
}

variable "server_ports" {
  description = "A dictionary mapping application layers to their ports"
  type = map(object({
    port        = number
    description = string
  }))
  default = {
    "http" = {
      port        = 80
      description = "Standard web traffic"
    }
  }
}

variable "enable_scaling_policy" {
  description = "If true, creates an Auto Scaling policy"
  type        = bool
  default     = false
}



variable "active_environment" { 
  description = "Which environment is currently active receiving traffic: blue or green"
  type        = string 
  
  validation {
    condition     = contains(["blue", "green"], var.active_environment)
    error_message = "Active environment must be exactly 'blue' or 'green'."
  }
}

variable "inactive_capacity" {
  description = "Capacity settings for the inactive Auto Scaling Group (usually 0)"
  type = object({
    min     = number
    max     = number
    desired = number
  })
  default = {
    min     = 0
    max     = 0
    desired = 0
  }
}