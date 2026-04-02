package test

import (
	"strings"
	"testing"
	"time"

	http_helper "github.com/gruntwork-io/terratest/modules/http-helper"
	"github.com/gruntwork-io/terratest/modules/terraform"
)

func TestProdEnvironmentEndToEnd(t *testing.T) {
	t.Parallel()

	// 1. Point directly to the production environment root folder
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../prod",
		// I didn't pass Vars here! 
		// Beacuse I want to test the exact variables hardcoded in the prod/main.tf
	})

	// 2. Always clean up
	defer terraform.Destroy(t, terraformOptions)

	// 3. Init and Apply the production environment
	terraform.InitAndApply(t, terraformOptions)

	// 4. Verify the production ALB
	albDnsName := terraform.Output(t, terraformOptions, "alb_dns_name")
	url := "http://" + albDnsName

	// 5. Assert we get the Prod response
	expectedText := "Welcome to the GREEN Environment! (prod)" // Assuming Green is active in prod
	
	http_helper.HttpGetWithRetryWithCustomValidation(
		t, url, nil, 30, 10*time.Second,
		func(status int, body string) bool {
			return status == 200 && strings.Contains(body, expectedText)
		},
	)
}

