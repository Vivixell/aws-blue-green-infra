# From Sandbox to Production: Building a Resilient AWS Blue/Green Infrastructure with Terraform

![banner](https://media2.dev.to/dynamic/image/width=1000,height=420,fit=cover,gravity=auto,format=auto/https%3A%2F%2Fdev-to-uploads.s3.amazonaws.com%2Fuploads%2Farticles%2Fv1cmhajw356kjfa3hgko.png)

There is a massive gap between Terraform code that simply "works" on your laptop and code that is truly production-ready. I recently tackled this exact gap as part of my 30-Day Terraform Challenge. The goal? Taking a standard AWS web server setup and transforming it into a reliable, modular, and secure system capable of handling zero-downtime Blue/Green deployments.

If you are looking to elevate your Infrastructure as Code (IaC) from basic scripts to robust, defensible architecture, this guide will walk you through the core principles of production-grade Terraform.

### Prerequisites
To follow along with the concepts in this guide, you should have:

* A basic understanding of AWS networking and compute (VPCs, ALBs, ASGs, EC2).
* Familiarity with standard Terraform commands and syntax.
* (Optional) Go installed on your machine if you wish to run the automated infrastructure tests.

### Tools Used
* **Terraform (>= 1.6.0):** Our core IaC engine.
* **AWS Provider (~> 6.9):** To interact with AWS APIs.
* **Terratest (Go):** For automated infrastructure validation.

### Folder Structure Overview
Production code cannot live in a single, monolithic `main.tf` file. It needs to be modular, allowing teams to compose infrastructure safely across different environments. We separated our reusable logic into a `modules` directory, and called it from environment-specific root folders.

```
.
├── modules/
│   └── webserver/
│       ├── main.tf
│       ├── variables.tf
|       ├── provider.tf
│       ├── outputs.tf
│       └── README.md
|   
├── dev/
│   ├── main.tf
|   ├── backend.tf
│   └── outputs.tf
├── prod/
│   ├── main.tf
|   ├── backend.tf
│   └── outputs.tf
└── test/
    └── webserver_test.go

```
*(Note: For complete usage instructions, inputs, and outputs of the module itself, you can check out the `README.md` in the repository's module folder!)*

---

### Step-by-Step Refactoring Guide

Here is a breakdown of the specific refactoring steps required to make this infrastructure production-grade.

#### 1. Reliability & Zero-Downtime Updates
Reliability means the system survives updates seamlessly. We implemented a **Blue/Green deployment strategy** using parallel Auto Scaling Groups (ASGs). To ensure updates happen without dropping traffic, we had to apply critical lifecycle rules.

**Before:** Modifying a launch template would immediately tear down running instances before the new ones were fully provisioned, causing an outage.

```
resource "aws_launch_template" "color" {
  name_prefix   = "${var.cluster_name}-lt-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
}
```
**After:** We explicitly instruct Terraform to provision the replacement infrastructure before destroying the old one. This is a non-negotiable for production compute.

```
resource "aws_launch_template" "color" {
  name_prefix   = "${var.cluster_name}-lt-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  
  lifecycle {
    create_before_destroy = true 
  }
}
```
#### 2. Security & Input Validation
Security isn't just about IAM roles and restricting Security Groups. It is also about protecting the deployment pipeline from human error. By adding strict input validation, we prevent invalid or highly expensive configurations from ever reaching the cloud.

**Before:** A developer could type any string for the environment variable.

```
variable "environment" {
  type = string
}
```
**After:** Terraform will immediately reject the apply if the inputs do not match our strict criteria, protecting our state and our AWS bill.

```
variable "environment" {
  description = "The deployment environment (e.g., dev, staging, prod)"
  type        = string
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be explicitly set to dev, staging, or prod."
  }
}
```
#### 3. Observability
You cannot fix what you cannot see. Production systems require automated monitoring and alerting out of the box. Instead of manually clicking through the AWS console later, I integrated CloudWatch alarms directly into the Terraform module.

We added a dynamic alarm that watches the CPU utilization of whichever ASG is currently active and routes alerts to an SNS topic.

```
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  for_each            = local.bg_envs
  alarm_name          = "${var.cluster_name}-high-cpu-${each.key}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 80
  
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.color[each.key].name
  }
  alarm_actions = [aws_sns_topic.alerts.arn]
}
```
#### 4. Automated Testing with Terratest
Manual testing is slow, expensive, and prone to oversight. To truly trust our infrastructure, we need automated tests. Using Terratest (a Go library developed by Gruntwork), we wrote a script that actively deploys the infrastructure to a sandbox, runs real-world HTTP checks against the Load Balancer, and then tears it all down.

```go

package test

import (
	"testing"
	"time"
	"github.com/gruntwork-io/terratest/modules/http-helper"
	"github.com/gruntwork-io/terratest/modules/terraform"
)

func TestWebserverCluster(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../dev",
		Vars: map[string]interface{}{
			"cluster_name":       "terratest-app",
			"environment":        "dev",
			"active_environment": "blue",
			"vpc_cidr":           "10.0.0.0/16",
			"instance_type":      "t3.micro",
			"asg_capacity": map[string]interface{}{
				"min": 1, "max": 1, "desired": 1,
			},
		},
	})

	// Crucial: Ensures the infrastructure is destroyed even if the test fails
	defer terraform.Destroy(t, terraformOptions)

	terraform.InitAndApply(t, terraformOptions)

	albDnsName := terraform.Output(t, terraformOptions, "alb_dns_name")
	url := "http://" + albDnsName

	// Asserts that the ALB is up and routing to the Blue environment
	http_helper.HttpGetWithRetry(t, url, nil, 200, "Welcome to the BLUE Environment!", 30, 10*time.Second)
}
```
**Why this matters:** Notice the `defer terraform.Destroy(t, terraformOptions)` line. Automated tests cost real money because they spin up real AWS resources. If an assertion fails halfway through, the Go test panics and stops. By deferring the destroy command, we guarantee that no matter what happens during the test run, the environment is cleanly destroyed at the end. No orphan resources, no surprise AWS bills.

### Final Thoughts
Terraform is incredibly powerful, but *how* you write it dictates whether your infrastructure is a liability or an asset. Moving from "it works" to "it's production-ready" requires a massive shift in mindset toward defensible code, strict boundaries, and automated safety nets. 

Have you implemented automated testing for your IaC yet? Let me know your preferred workflow in the comments!