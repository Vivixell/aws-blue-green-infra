output "alb_dns_name" {
  description = "The DNS name of the Application Load Balancer"
  value       = aws_lb.alb.dns_name
}

output "vpc_id" {
  description = "The ID of the VPC created by the module"
  value       = aws_vpc.this.id
}

output "asg_names" {
  description = "A map containing the names of the Blue and Green Auto Scaling Groups"
  value       = { for k, asg in aws_autoscaling_group.color : k => asg.name }
}

output "private_subnet_map" {
  description = "A map of private subnet keys to their actual AWS Subnet IDs"
  value       = { for k, subnet in aws_subnet.private : k => subnet.id }
}