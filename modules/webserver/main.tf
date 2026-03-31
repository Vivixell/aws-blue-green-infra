data "aws_availability_zones" "available" {
  state = "available"
}

# ==========================================
# 1. STANDARDIZED TAGGING (Day 16 Checklist)
# ==========================================
locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Project     = var.cluster_name
  }
  
  # The two environments we want to build simultaneously
  bg_envs = toset(["blue", "green"]) 
}

# ==========================================
# 2. NETWORKING
# ==========================================
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  tags = merge(local.common_tags, { Name = "${var.cluster_name}-vpc" })
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.common_tags, { Name = "${var.cluster_name}-igw" })
}

resource "aws_subnet" "public" {
  for_each          = var.public_subnet_cidr
  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.cidr_block
  availability_zone = data.aws_availability_zones.available.names[each.value.az_index]
  tags              = merge(local.common_tags, { Name = "${var.cluster_name}-public-${each.key}" })
}

resource "aws_subnet" "private" {
  for_each          = var.private_subnet_cidr
  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.cidr_block
  availability_zone = data.aws_availability_zones.available.names[each.value.az_index]
  tags              = merge(local.common_tags, { Name = "${var.cluster_name}-private-${each.key}" })
}

resource "aws_nat_gateway" "regional_nat" {
  # Allocating an EIP for production reliability
  allocation_id     = aws_eip.nat.id 
  subnet_id         = aws_subnet.public[keys(var.public_subnet_cidr)[0]].id
  tags              = merge(local.common_tags, { Name = "${var.cluster_name}-regional-nat" })
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = merge(local.common_tags, { Name = "${var.cluster_name}-nat-eip" })
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = merge(local.common_tags, { Name = "${var.cluster_name}-public-rt" })
}

resource "aws_route_table_association" "public_assoc" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.regional_nat.id
  }
  tags = merge(local.common_tags, { Name = "${var.cluster_name}-private-rt" })
}

resource "aws_route_table_association" "private_assoc" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_rt.id
}

# ==========================================
# 3. SECURITY (Day 16 Checklist)
# ==========================================
resource "aws_security_group" "alb_sg" {
  name_prefix = "${var.cluster_name}-alb-sg-"
  description = "Allow HTTP inbound for ${var.cluster_name}"
  vpc_id      = aws_vpc.this.id
  tags        = merge(local.common_tags, { Name = "${var.cluster_name}-alb-sg" })
  
  lifecycle { create_before_destroy = true }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = var.server_ports["http"].port
  to_port           = var.server_ports["http"].port
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_all_out" {
  security_group_id = aws_security_group.alb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_security_group" "instance_sg" {
  name_prefix = "${var.cluster_name}-instance-sg-"
  description = "Strictly allow traffic from ALB only"
  vpc_id      = aws_vpc.this.id
  tags        = merge(local.common_tags, { Name = "${var.cluster_name}-instance-sg" })
  
  lifecycle { create_before_destroy = true }
}

resource "aws_vpc_security_group_ingress_rule" "instance_http" {
  security_group_id            = aws_security_group.instance_sg.id
  referenced_security_group_id = aws_security_group.alb_sg.id
  from_port                    = var.server_ports["http"].port
  to_port                      = var.server_ports["http"].port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "instance_all_out" {
  security_group_id = aws_security_group.instance_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ==========================================
# 4. BLUE/GREEN LOAD BALANCING 
# ==========================================
resource "aws_lb" "alb" {
  name               = "${var.cluster_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [for subnet in aws_subnet.public : subnet.id]
  tags               = merge(local.common_tags, { Name = "${var.cluster_name}-alb" })
}

resource "aws_lb_target_group" "color" {
  for_each = local.bg_envs

  name     = "${var.cluster_name}-tg-${each.key}"
  port     = var.server_ports["http"].port
  protocol = "HTTP"
  vpc_id   = aws_vpc.this.id
  
  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
  tags = merge(local.common_tags, { Name = "${var.cluster_name}-tg-${each.key}" })
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = var.server_ports["http"].port
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    # The actual Blue/Green switch based on variable injection
    target_group_arn = var.active_environment == "blue" ? aws_lb_target_group.color["blue"].arn : aws_lb_target_group.color["green"].arn
  }
}

# ==========================================
# 5. COMPUTE & RELIABILITY (Day 16 Checklist)
# ==========================================
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_launch_template" "color" {
  for_each = local.bg_envs

  name_prefix   = "${var.cluster_name}-lt-${each.key}-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.instance_sg.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y apache2
    systemctl start apache2
    systemctl enable apache2
    echo "<h1>Welcome to the ${upper(each.key)} Environment! (${var.environment})</h1>" > /var/www/html/index.html
  EOF
  )

  lifecycle {
    create_before_destroy = true # Essential for zero-downtime LT updates
  }
  tags = merge(local.common_tags, { Name = "${var.cluster_name}-lt-${each.key}" })
}

resource "aws_autoscaling_group" "color" {
  for_each = local.bg_envs

  name_prefix         = "${var.cluster_name}-asg-${each.key}-"
  # desired_capacity    = var.asg_capacity.desired
  # max_size            = var.asg_capacity.max
  # min_size            = var.asg_capacity.min
  # Had to edit the ASG capacity settings to allow for inactive environments to have 0 desired and min capacity while still being able to scale up when switched to active. This is a common pattern in blue/green deployments to save costs on the inactive environment.
  # If the ASG color matches the active_environment, use normal capacity. Otherwise, use inactive capacity.
  
  desired_capacity    = each.key == var.active_environment ? var.asg_capacity.desired : var.inactive_capacity.desired
  max_size            = each.key == var.active_environment ? var.asg_capacity.max : var.inactive_capacity.max
  min_size            = each.key == var.active_environment ? var.asg_capacity.min : var.inactive_capacity.min

  vpc_zone_identifier = [for subnet in aws_subnet.private : subnet.id]
  target_group_arns   = [aws_lb_target_group.color[each.key].arn]

  health_check_type         = "ELB" # Required by Day 16 checklist
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.color[each.key].id
    version = aws_launch_template.color[each.key].latest_version
  }

  dynamic "tag" {
    for_each = merge(local.common_tags, { Name = "${var.cluster_name}-asg-${each.key}" })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  depends_on = [
    aws_nat_gateway.regional_nat,
    aws_route_table_association.private_assoc
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# ==========================================
# 6. OBSERVABILITY (Day 16 Checklist)
# ==========================================
resource "aws_sns_topic" "alerts" {
  name = "${var.cluster_name}-cpu-alerts"
  tags = local.common_tags
}

# Creates a CPU alarm for both Blue and Green ASGs to monitor traffic spikes
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  for_each = local.bg_envs

  alarm_name          = "${var.cluster_name}-high-cpu-${each.key}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Triggers when ${upper(each.key)} CPU exceeds 80% for 4 minutes"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.color[each.key].name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  tags          = local.common_tags
}