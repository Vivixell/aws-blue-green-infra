# ==========================================
# ROOT OUTPUTS
# ==========================================
output "prod_alb_dns" {
  value = module.webserver.alb_dns_name
}

output "prod_private_subnets" {
  value = module.webserver.private_subnet_map
}

output "prod_asg_names" {
  value = module.webserver.asg_names
}

output "alb_dns_name" {
  description = "The DNS name of the Application Load Balancer to access the environment."
  value       = module.webserver.alb_dns_name
}

output "active_environment_asgs" {
  description = "The names of the Auto Scaling Groups currently provisioned."
  value       = module.webserver.asg_names
}

