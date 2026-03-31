package test

import (
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/http-helper"
	"github.com/gruntwork-io/terratest/modules/terraform"
)

func TestWebserverCluster(t *testing.T) {
	t.Parallel()

	// Define the Terraform options and variables to pass to your module
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		// The path to where your Terraform code is located
		TerraformDir: "../dev", 

		// Variables to pass to our Terraform code using -var options
		Vars: map[string]interface{}{
			"cluster_name":       "terratest-app",
			"environment":        "dev",
			"active_environment": "blue",
			"vpc_cidr":           "10.0.0.0/16",
			"instance_type":      "t3.micro",
			"asg_capacity": map[string]interface{}{
				"min":     1,
				"max":     1,
				"desired": 1,
			},
		},
	})

	// Defer the destroy so it cleans up the infrastructure after the test finishes, even if it fails
	defer terraform.Destroy(t, terraformOptions)

	// This will run `terraform init` and `terraform apply` and fail the test if there are any errors
	terraform.InitAndApply(t, terraformOptions)

	// Run `terraform output` to get the value of an output variable
	albDnsName := terraform.Output(t, terraformOptions, "alb_dns_name")
	url := "http://" + albDnsName

	// Verify that we get back a 200 OK with the expected text from the Blue environment
	expectedText := "Welcome to the BLUE Environment!"
	
	// Make an HTTP request to the URL and retry if it fails (wait up to 30 times, 10 seconds between retries)
	http_helper.HttpGetWithRetry(t, url, nil, 200, expectedText, 30, 10*time.Second)
}