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
	terraformOptions := &terraform.Options{
		// The path to where our Terraform code is located.
		TerraformDir: "../",

		// --- THIS IS THE FIX ---
		// Explicitly tell Terratest to use the "terraform" binary.
		// This prevents it from defaulting to "tofu".
		TerraformBinary: "terraform",
	}

	// --- Test Lifecycle ---
	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// --- Validation ---
	awsRegion := terraform.Output(t, terraformOptions, "region")
	clientInstances := terraform.OutputListOfObjects(t, terraformOptions, "client_instances")

	require.NotEmpty(t, clientInstances, "Client instances output should not be empty")
	instanceID := clientInstances[0]["id"].(string)

	// AWS SDK Validation
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

	terraformOptions := &terraform.Options{
		TerraformDir: "../",
		
		// Add the fix here as well.
		TerraformBinary: "terraform",
	}

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	storageInstances := terraform.OutputListOfObjects(t, terraformOptions, "storage_instances")
	require.NotEmpty(t, storageInstances, "Storage instances output should not be empty")
}
