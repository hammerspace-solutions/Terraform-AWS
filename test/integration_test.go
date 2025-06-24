package test

import (
	"context"
	"testing"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/ec2"
	"github.com/aws/aws-sdk-go-v2/service/ec2/types"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestClientModule(t *testing.T) {
	t.Parallel()

	// --- Test Setup ---
	// This options struct is now very simple.
	// Terratest will automatically find and use any environment variables
	// in the CI/CD environment that start with "TF_VAR_" and pass them to Terraform.
	// We do not need to read them manually in Go.
	terraformOptions := &terraform.Options{
		// The path to where our Terraform code is located.
		TerraformDir: "../",
	}

	// --- Test Lifecycle ---
	// Defer the destroy command to ensure cleanup happens automatically.
	defer terraform.Destroy(t, terraformOptions)

	// Run `terraform init` and `terraform apply`.
	// Terratest passes the TF_VAR_ environment variables to this command.
	terraform.InitAndApply(t, terraformOptions)

	// --- Validation ---
	// After the apply, get all the necessary info from Terraform outputs.
	awsRegion := terraform.Output(t, terraformOptions, "region")
	clientInstances := terraform.OutputListOfObjects(t, terraformOptions, "client_instances")

	// Assert that we got at least one instance back.
	require.NotEmpty(t, clientInstances, "Client instances output should not be empty")

	// Get the ID of the first instance for deeper validation.
	instanceID := clientInstances[0]["id"].(string)

	// Use the AWS SDK to verify the instance was actually created and is running.
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion(awsRegion))
	require.NoError(t, err, "Failed to load AWS configuration")

	ec2Client := ec2.NewFromConfig(cfg)
	describeInput := &ec2.DescribeInstancesInput{
		InstanceIds: []string{instanceID},
	}
	describeOutput, err := ec2Client.DescribeInstances(context.TODO(), describeInput)

	require.NoError(t, err, "Failed to describe EC2 instance")
	require.Equal(t, 1, len(describeOutput.Reservations), "Expected 1 reservation from AWS API")
	require.Equal(t, 1, len(describeOutput.Reservations[0].Instances), "Expected 1 instance in the reservation")

	apiInstance := describeOutput.Reservations[0].Instances[0]
	assert.Equal(t, types.InstanceStateNameRunning, apiInstance.State.Name, "Instance is not in 'running' state")
}

// You can add other tests here (e.g., TestStorageModule) following the same simple pattern.
func TestStorageModule(t *testing.T) {
	t.Parallel()

	// This test would be similar to the client test, but would set
	// TF_VAR_deploy_components to '["storage"]' in the CI workflow
	// and would validate the storage_instances output.
}
