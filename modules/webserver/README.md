# AWS Blue/Green Deployment Module

This Terraform module provisions a highly available, standardized AWS infrastructure designed for Blue/Green deployments. It handles VPC creation, security groups, Application Load Balancing, and sets up parallel Auto Scaling Groups (ASGs) representing "Blue" and "Green" environments.

## Architecture & Features

* **Networking:** Custom VPC, Internet Gateway, Regional NAT Gateway (with EIP), and dynamic Public/Private subnets distributed across Availability Zones.
* **Security:** Strict security group rules. The ASG instances only accept traffic routed through the Application Load Balancer.
* **Compute:** Parallel Auto Scaling Groups ("Blue" and "Green") using Ubuntu 22.04 LTS via Launch Templates.
* **Traffic Routing:** An Application Load Balancer (ALB) that routes traffic to either the Blue or Green target group based on a single variable toggle.
* **Observability:** Integrated CloudWatch alarms monitoring CPU utilization across both environments, hooked into an SNS topic for alerting.

## Requirements

| Name | Version |
|------|---------|
| terraform | `>= 1.6.0` |
| aws | `~> 6.9` |

## Inputs

| Name | Description | Type | Required | Default |
|------|-------------|------|:--------:|---------|
| `cluster_name` | The name prefix to use for all cluster resources. | `string` | **Yes** | n/a |
| `environment` | The deployment environment. Must be `dev`, `staging`, or `prod`. | `string` | **Yes** | n/a |
| `active_environment` | Determines which ASG receives live traffic. Must be `blue` or `green`. | `string` | **Yes** | n/a |
| `vpc_cidr` | The CIDR block for the VPC. | `string` | **Yes** | n/a |
| `public_subnet_cidr` | Map defining CIDR blocks and AZ indexes for public subnets. | `map(object({cidr_block=string, az_index=number}))` | **Yes** | n/a |
| `private_subnet_cidr` | Map defining CIDR blocks and AZ indexes for private subnets. | `map(object({cidr_block=string, az_index=number}))` | **Yes** | n/a |
| `instance_type` | EC2 instance type. Restricted to t2/t3 micro, small, or medium. | `string` | **Yes** | n/a |
| `asg_capacity` | Object defining min, max, and desired capacity for the ASGs. | `object({min=number, max=number, desired=number})` | **Yes** | n/a |
| `server_ports` | Dictionary mapping application layers to their ports. | `map(object({port=number, description=string}))` | No | `{"http": {port: 80, ...}}` |
| `enable_scaling_policy` | Boolean to trigger Auto Scaling policy creation. | `bool` | No | `false` |


## Outputs

| Name | Description |
|------|-------------|
| `alb_dns_name` | The DNS name of the Application Load Balancer to access the application. |
| `vpc_id` | The ID of the VPC created by the module. |
| `asg_names` | A map containing the names of the created Blue and Green Auto Scaling Groups. |
| `private_subnet_map` | A map linking your private subnet keys to their actual AWS Subnet IDs. |

## Usage Note

To switch traffic between environments, update the `active_environment` variable in your root module from `"blue"` to `"green"` (or vice-versa) and run `terraform apply`. The ALB listener will dynamically update its target group routing while leaving the underlying compute intact.