package test

import (
	"context"
	"fmt"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/ec2"
	"github.com/aws/aws-sdk-go-v2/service/ec2/types"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.comcom/stretchr/testify/require"
)

// NOTE: The getRequiredEnvVar helper function is in test_helpers.go

func TestStorageModuleWithRAID(t *testing.T) {
	t.Parallel()

	// --- Test Setup: Define shared variables ---
	// We are defining these outside the loop as they are the same for all tests.
	// The `env` block in the GitHub Actions workflow provides their values.
	sharedVars := map[string]interface{}{
		"REGION":      getRequiredEnvVar(t, "REGION"),
		"VPC_ID":      getRequiredEnvVar(t, "VPC_ID"),
		"SUBNET_ID":   getRequiredEnvVar(t, "SUBNET_ID"),
		"KEY_NAME":    getRequiredEnvVar(t, "KEY_NAME"),
		"STORAGE_AMI": getRequiredEnvVar(t, "STORAGE_AMI"),
	}

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
		tc := tc
		t.Run(testName, func(t *testing.T) {
			t.Parallel()

			// --- THIS IS THE FIX ---
			// Copy the 'examples' folder to a temporary, isolated directory for this test run.
			// This ensures that each parallel test has its own .tfstate file.
			tempTestFolder := test_structure.CopyTerraformFolderToTemp(t, "../modules/storage_servers", "examples")

			projectName := fmt.Sprintf("terratest-storage-%s-%s", tc.raidLevel, random.UniqueId())

			terraformOptions := &terraform.Options{
				// Point to the temporary directory instead of the original.
				TerraformDir:    tempTestFolder,
				TerraformBinary: "terraform",
				Vars: map[string]interface{}{
					"project_name":           projectName,
					"region":                 sharedVars["REGION"],
					"vpc_id":                 sharedVars["VPC_ID"],
					"subnet_id":              sharedVars["SUBNET_ID"],
					"key_name":               sharedVars["KEY_NAME"],
					"storage_ami":            sharedVars["STORAGE_AMI"],
					"storage_instance_count": 1,
					"storage_ebs_count":      tc.diskCount,
					"storage_raid_level":     tc.raidLevel,
					"storage_user_data":      "../../../templates/storage_server_ubuntu.sh",
				},
			}

			defer terraform.Destroy(t, terraformOptions)
			terraform.InitAndApply(t, terraformOptions)

			// --- Validation ---
			awsRegion := terraform.Output(t, terraformOptions, "region")
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
