// test/clients_test.go
package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

func TestTerraformClientsModule(t *testing.T) {
	t.Parallel()

	// Pick a random AWS region to support running tests in parallel.
	awsRegion := aws.GetRandomStableRegion(t, nil, nil)

	// Define the input variables for our test. We'll deploy one client.
	terraformOptions := &terraform.Options{
		// The path to where our Terraform code is located
		TerraformDir: "../",

		// Variables to pass to our Terraform code using -var options
		Vars: map[string]interface{}{
			"deploy_components":      []string{"clients"},
			"clients_instance_count": 1,
			"project_name":           "terratest-clients",
			"region":                 awsRegion,
			// You must provide real values for your required variables
			"vpc_id":      "vpc-xxxxxxxx",
			"subnet_id":   "subnet-xxxxxxxx",
			"key_name":    "your-test-key",
			"clients_ami": "ami-xxxxxxxx", // A valid AMI for the region
		},
	}

	// At the end of the test, run `terraform destroy` to clean up any resources
	defer terraform.Destroy(t, terraformOptions)

	// Run `terraform init` and `terraform apply`
	terraform.InitAndApply(t, terraformOptions)

	// Run `terraform output` to get the value of an output variable
	// We get the list of instance details that our module outputs.
	clientInstances := terraform.OutputList(t, terraformOptions, "client_instances")

	// 1. VERIFY that one instance was created.
	assert.Equal(t, 1, len(clientInstances), "Should have created one client instance")

	// 2. VERIFY the instance in AWS
	// Get the first instance map from the list
	instanceDetailsMap := clientInstances[0]
	// Get the instance ID from the map
	instanceID := instanceDetailsMap["id"].(string)

	// Use the AWS SDK to go look up the instance and get its details
	instance := aws.GetEc2Instance(t, awsRegion, instanceID)

	// 3. VERIFY it has the correct project tag
	assert.Equal(t, "terratest-clients", instance.Tags["Project"], "Instance should have the correct Project tag")
}
