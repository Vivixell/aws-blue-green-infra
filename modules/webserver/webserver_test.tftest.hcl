

# 1. Setup default variables to pass validation rules
variables {
  cluster_name       = "unit-test-cluster"
  environment        = "dev"
  active_environment = "blue"
  vpc_cidr           = "10.0.0.0/16"

  public_subnet_cidr = {
    "zone1" = { cidr_block = "10.0.1.0/24", az_index = 0 }
  }
  private_subnet_cidr = {
    "zone1" = { cidr_block = "10.0.10.0/24", az_index = 0 }
  }

  instance_type = "t3.micro"

  asg_capacity = {
    min     = 2
    max     = 4
    desired = 2
  }
  # Note: inactive_capacity falls back to the default of 0
}

# 2. Test Security Group configuration
run "validate_alb_security_group" {
  command = plan

  assert {
    condition     = aws_vpc_security_group_ingress_rule.alb_http.from_port == 80
    error_message = "ALB Security Group must allow ingress on port 80."
  }
}

# 3. Test Blue/Green Routing and Capacity Logic
run "validate_blue_green_capacity_logic" {
  command = plan

  assert {
    condition     = aws_autoscaling_group.color["blue"].desired_capacity == 2
    error_message = "Active environment (Blue) did not receive the correct desired capacity."
  }

  assert {
    condition     = aws_autoscaling_group.color["green"].desired_capacity == 0
    error_message = "Inactive environment (Green) did not scale down to 0."
  }
}

# 4. Test Resource Property Assignments
run "validate_instance_type_assignment" {
  command = plan

  assert {
    condition     = aws_launch_template.color["blue"].instance_type == "t3.micro"
    error_message = "Launch template did not assign the correct instance type."
  }
}