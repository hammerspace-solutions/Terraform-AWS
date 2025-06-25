package test

import (
	"context"
	"fmt"
	"os"
	"testing"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/ec2"
	"github.com/aws/aws-sdk-go-v2/service/ec2/types"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Helper function to get required environment variables for the test.
func getRequiredEnvVar(t *testing.T, key string) string {
	value, found := os.LookupEnv(key)
	require.True(t, found, "Environment variable '%s' must be set for this test", key)
	return value
}

// TestClientModule runs an isolated integration test for the clients module.
func TestClientModule(t *testing.T) {
	t.Parallel()

	// --- Test Setup ---
	// These variables will be passed from the CI workflow (GitHub Actions)
	awsRegion := getRequiredEnvVar(t, "REGION")
	vpcId := getRequiredEnvVar(t, "VPC_ID")
	subnetId := getRequiredEnvVar(t, "SUBNET_ID")
	keyName := getRequiredEnvVar(t, "KEY_NAME")
	clientsAmi := getRequiredEnvVar(t, "CLIENTS_AMI")
	
	projectName := fmt.Sprintf("terratest-clients-%s", random.UniqueId())

	// Configure Terraform options to point to the isolated example directory.
	terraformOptions := &terraform.Options{
		// MODIFIED: Point to the new example directory for the clients module.
		TerraformDir:    "../modules/clients/examples",
		TerraformBinary: "terraform",

		// Pass the required variables to the example's terraform.tfvars.
		Vars: map[string]interface{}{
			"project_name":           projectName,
			"region":                 awsRegion,
			"vpc_id":                 vpcId,
			"subnet_id":              subnetId,
			"key_name":               keyName,
			"clients_ami":            clientsAmi,
			"clients_instance_count": 1,
		},
	}

	// --- Test Lifecycle ---
	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// --- Validation ---
	clientInstances := terraform.OutputListOfObjects(t, terraformOptions, "client_instances")
	require.Equal(t, 1, len(clientInstances), "Expected to find 1 client instance in the output")
	
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

// To test the storage module, you would create a similar examples directory
// under `modules/storage_servers/examples/` and create a `TestStorageModule` function.
