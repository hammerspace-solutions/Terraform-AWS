package test

import (
	"context"
	"fmt"
	"os"
	"strconv"
	"testing"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/ec2"
	"github.com/aws/aws-sdk-go-v2/service/ec2/types"
	"github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Helper function to read a required environment variable and fail the test if it's not set.
func getRequiredEnvVar(t *testing.T, key string) string {
	value, found := os.LookupEnv(key)
	require.True(t, found, "Environment variable '%s' must be set for this test", key)
	return value
}

// TestClientModule runs an integration test for the "clients" module.
func TestClientModule(t *testing.T) {
	t.Parallel()

	// --- Test Setup ---
	awsRegion := getRequiredEnvVar(t, "REGION")
	projectName := fmt.Sprintf("terratest-client-%s", random.UniqueId())

	vpcId := getRequiredEnvVar(t, "VPC_ID")
	subnetId := getRequiredEnvVar(t, "SUBNET_ID")
	keyName := getRequiredEnvVar(t, "KEY_NAME")
	clientsAmi := getRequiredEnvVar(t, "CLIENTS_AMI")
	clientsInstanceType := getRequiredEnvVar(t, "CLIENTS_INSTANCE_TYPE")

	clientsInstanceCountStr := getRequiredEnvVar(t, "CLIENTS_INSTANCE_COUNT")
	clientsInstanceCount, err := strconv.Atoi(clientsInstanceCountStr)
	require.NoError(t, err, "CLIENTS_INSTANCE_COUNT must be a valid integer")

	terraformOptions := &terraform.Options{
		TerraformDir: "../",
		Vars: map[string]interface{}{
			"project_name":                        projectName,
			"deploy_components":                   []string{"clients"},
			"vpc_id":                              vpcId,
			"subnet_id":                           subnetId,
			"key_name":                            keyName,
			"clients_ami":                         clientsAmi,
			"clients_instance_count":              clientsInstanceCount,
			"clients_instance_type":               clientsInstanceType,
			"region":                              awsRegion,
			"availability_zone":                   aws.GetAvailabilityZones(t, awsRegion)[0],
			"capacity_reservation_create_timeout": "0s",
		},
	}

	// --- Test Lifecycle ---
	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// --- Validation ---
	// MODIFIED: Use OutputListOfObjects to correctly parse the complex output.
	clientInstances := terraform.OutputListOfObjects(t, terraformOptions, "client_instances")
	require.Equal(t, clientsInstanceCount, len(clientInstances), "Number of client instances in output does not match expected count")
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

// TestStorageModule runs an integration test for the "storage_servers" module.
func TestStorageModule(t *testing.T) {
	t.Parallel()

	// --- Test Setup ---
	awsRegion := getRequiredEnvVar(t, "REGION")
	projectName := fmt.Sprintf("terratest-storage-%s", random.UniqueId())

	vpcId := getRequiredEnvVar(t, "VPC_ID")
	subnetId := getRequiredEnvVar(t, "SUBNET_ID")
	keyName := getRequiredEnvVar(t, "KEY_NAME")
	storageAmi := getRequiredEnvVar(t, "STORAGE_AMI")

	storageInstanceCountStr := getRequiredEnvVar(t, "STORAGE_INSTANCE_COUNT")
	storageInstanceCount, err := strconv.Atoi(storageInstanceCountStr)
	require.NoError(t, err, "STORAGE_INSTANCE_COUNT must be a valid integer")

	terraformOptions := &terraform.Options{
		TerraformDir: "../",
		Vars: map[string]interface{}{
			"project_name":                        projectName,
			"vpc_id":                              vpcId,
			"subnet_id":                           subnetId,
			"key_name":                            keyName,
			"storage_ami":                         storageAmi,
			"region":                              awsRegion,
			"availability_zone":                   aws.GetAvailabilityZones(t, awsRegion)[0],
			"deploy_components":                   []string{"storage"},
			"storage_instance_count":              storageInstanceCount,
			"storage_ebs_count":                   3, // Minimum for RAID-5
			"storage_raid_level":                  "raid-5",
			"capacity_reservation_create_timeout": "0s",
		},
	}

	// --- Test Lifecycle ---
	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// --- Validation ---
	// MODIFIED: Use OutputListOfObjects to correctly parse the complex output.
	storageInstances := terraform.OutputListOfObjects(t, terraformOptions, "storage_instances")
	require.Equal(t, storageInstanceCount, len(storageInstances), "Number of storage instances does not match expected count")
	require.NotEmpty(t, storageInstances, "Storage instances output should not be empty")

	instanceID := storageInstances[0]["id"].(string)
	assert.NotEmpty(t, instanceID, "Storage instance ID should not be empty")
}
