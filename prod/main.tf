module "webserver" {
  source = "../modules/webserver"

  # 1. Identity & Environment
  cluster_name       = "prod-app"
  environment        = "prod"
  active_environment = "green" # The traffic switch! Change to "blue" and apply to route traffic.

  # 2. Networking
  vpc_cidr = "10.1.0.0/16"

  public_subnet_cidr = {
    "public-a" = { cidr_block = "10.1.1.0/24", az_index = 0 }
    "public-b" = { cidr_block = "10.1.2.0/24", az_index = 1 }
  }

  private_subnet_cidr = {
    "private-a" = { cidr_block = "10.1.11.0/24", az_index = 0 }
    "private-b" = { cidr_block = "10.1.12.0/24", az_index = 1 }
  }

  # 3. Compute Capacity
  instance_type = "t3.small" # Passed validation!

  # Capacity for the ACTIVE environment receiving traffic
  asg_capacity = {
    min     = 2
    max     = 6
    desired = 2
  }

  # Capacity for the INACTIVE environment. 
  # Currently set to match active for testing/rollback readiness.
  # Change min, max, and desired to 0 to safely scale down and save costs.
  
  inactive_capacity = {
    min     = 0 #2 but I'm currently scaling to zero as I've switched active environment to green and want to save costs while I test/validate the new environment.
    max     = 6
    desired = 0 #2 
  }

  server_ports = {
    "http" = {
      port        = 80
      description = "Standard HTTP Port"
    }
  }

  # 4. Optional Toggles
  enable_scaling_policy = true
}