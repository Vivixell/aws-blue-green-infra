package test

import (
	
	"strings"
	"testing"
	"time"

	http_helper "github.com/gruntwork-io/terratest/modules/http-helper"
	"github.com/gruntwork-io/terratest/modules/terraform"
)

func TestWebserverClusterIntegration(t *testing.T) {
	// Runs tests in parallel if you add more test functions later
	t.Parallel()

	// 1. Configure Terraform options and inputs
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		// Point directly to the module folder to test the reusable code
		TerraformDir: "../modules/webserver",

		// Supply the variables required to deploy. 
		// We use minimal capacity and instances to save money during the test run.
		Vars: map[string]interface{}{
			"cluster_name":       "terratest-cluster",
			"environment":        "dev",
			"active_environment": "blue",
			"vpc_cidr":           "10.2.0.0/16",
			"public_subnet_cidr": map[string]interface{}{
				"zone-a": map[string]interface{}{"cidr_block": "10.2.1.0/24", "az_index": 0},
				"zone-b": map[string]interface{}{"cidr_block": "10.2.2.0/24", "az_index": 1},
			},
			"private_subnet_cidr": map[string]interface{}{
				"zone-a": map[string]interface{}{"cidr_block": "10.2.11.0/24", "az_index": 0},
				"zone-b": map[string]interface{}{"cidr_block": "10.2.12.0/24", "az_index": 1},
			},
			"instance_type": "t3.micro",
			"asg_capacity": map[string]interface{}{
				"min":     1,
				"max":     1,
				"desired": 1,
			},
		},
	})

	// 2. CRITICAL: Ensure resources are destroyed at the end, even if the test fails!
	defer terraform.Destroy(t, terraformOptions)

	// 3. Deploy the infrastructure (terraform init && terraform apply)
	terraform.InitAndApply(t, terraformOptions)

	// 4. Extract the ALB DNS name from the outputs
	albDnsName := terraform.Output(t, terraformOptions, "alb_dns_name")
	url := "http://" + albDnsName

	// 5. Verify the ALB returns a 200 OK and the correct Blue Environment text
	// We retry 30 times with a 10-second sleep between retries because EC2/ALB takes time to boot.
	// expectedBody := "Welcome to the BLUE Environment! (dev)"
	// http_helper.HttpGetWithRetry(t, url, nil, 200, expectedBody, 30, 10*time.Second) #this didn't work because the body contains additional text like HTML tags, so we need a custom validation function instead

	expectedText := "Welcome to the BLUE Environment! (dev)"
	
	http_helper.HttpGetWithRetryWithCustomValidation(
		t,
		url,
		nil,
		30,
		10*time.Second,
		func(status int, body string) bool {
			// Check if status is 200 AND the body contains our expected text string
			return status == 200 && strings.Contains(body, expectedText)
		},
	)
}