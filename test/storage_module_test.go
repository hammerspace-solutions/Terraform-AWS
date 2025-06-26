package test

import (
	"context"
	"fmt"
	"os"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/ec2"
	"github.com/aws/aws-sdk-go-v2/service/ec2/types"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/require"
)

// Helper function to read a required environment variable and fail the test if it's not set.
// This is crucial for running tests in a CI/CD environment.
func getRequiredEnvVar(t *testing.T, key string) string {
	value, found := os.LookupEnv(key)
	require.True(t, found, "Environment variable '%s' must be set for this test", key)
	return value
}

// TestStorageModuleWithRAID runs a suite of integration tests for the storage_servers module.
func TestStorageModuleWithRAID(t *testing.T) {
	t.Parallel()

	// --- Test Setup: Read shared variables from the environment once ---
	// These are read from the `env:` block in the GitHub Actions workflow.
	awsRegion := getRequiredEnvVar(t, "REGION")
	vpcId := getRequiredEnvVar(t, "VPC_ID")
	subnetId := getRequiredEnvVar(t, "SUBNET_ID")
	keyName := getRequiredEnvVar(t, "KEY_NAME")
	storageAmi := getRequiredEnvVar(t, "STORAGE_AMI")

	// Define the test cases for each RAID level.
	testCases := map[string]struct {
		raidLevel string
		diskCount int
	}{
		"RAID-0": {raidLevel: "raid-0", diskCount: 2},
		"RAID-5": {raidLevel: "raid-5", diskCount: 3},
		"RAID-6": {raidLevel: "raid-6", diskCount: 4},
	}

	for testName, tc := range testCases {
		tc := tc // Capture range variable
		t.Run(testName, func(t *testing.T) {
			t.Parallel()

			projectName := fmt.Sprintf("terratest-storage-%s-%s", tc.raidLevel, random.UniqueId())

			terraformOptions := &terraform.Options{
				TerraformDir:    "../modules/storage_servers/examples",
				TerraformBinary: "terraform",
				Vars: map[string]interface{}{
					// Pass the variables read from the environment
					"project_name":           projectName,
					"region":                 awsRegion,
					"vpc_id":                 vpcId,
					"subnet_id":              subnetId,
					"key_name":               keyName,
					"storage_ami":            storageAmi,
					// Pass test-specific variables
					"storage_instance_count": 1,
					"storage_ebs_count":      tc.diskCount,
					"storage_raid_level":     tc.raidLevel,
					"storage_user_data":      "../../../templates/storage_server_ubuntu.sh",
				},
			}

			defer terraform.Destroy(t, terraformOptions)
			terraform.InitAndApply(t, terraformOptions)

			// --- Validation ---
			storageInstances := terraform.OutputListOfObjects(t, terraformOptions, "storage_instances")
			require.Len(t, storageInstances, 1, "Expected to find 1 storage instance")

			instanceID := storageInstances[0]["id"].(string)

			cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion(awsRegion))
			require.NoError(t, err, "Failed to load AWS configuration")
			ec2Client := ec2.NewFromConfig(cfg)

			describeVolumesInput := &ec2.DescribeVolumesInput{
				Filters: []types.Filter{
					{
						Name:   aws.String("attachment.instance-id"),
						Values: []string{instanceID},
					},
				},
			}
			describeVolumesOutput, err := ec2Client.DescribeVolumes(context.TODO(), describeVolumesInput)
			require.NoError(t, err, "Failed to describe EBS volumes")

			expectedTotalVols := 1 + tc.diskCount
			require.Len(t, describeVolumesOutput.Volumes, expectedTotalVols, "Incorrect number of EBS volumes attached to instance %s", instanceID)

			t.Logf("Successfully validated creation of %d total volumes for %s test.", expectedTotalVols, testName)
		})
	}
}
