
module "blue_green_app" {
  source = "../modules/webserver" # Assumes your dev folder is adjacent to the modules folder

  cluster_name       = "dev-app"
  environment        = "dev"
  active_environment = "blue" # Toggle to "green" when ready to route traffic

  # Networking Setup
  vpc_cidr = "10.0.0.0/16"
  
  public_subnet_cidr = {
    "zone1" = { cidr_block = "10.0.1.0/24", az_index = 0 }
    "zone2" = { cidr_block = "10.0.2.0/24", az_index = 1 }
  }

  private_subnet_cidr = {
    "zone1" = { cidr_block = "10.0.10.0/24", az_index = 0 }
    "zone2" = { cidr_block = "10.0.20.0/24", az_index = 1 }
  }

  # Compute Setup
  instance_type = "t3.micro"
  
  asg_capacity = {
    min     = 2
    max     = 4
    desired = 2
  }

  # Optional: enable_scaling_policy and server_ports will use the defaults defined in the module
}