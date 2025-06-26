package test

import (
	"context"
	"fmt"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws" // Use the official AWS SDK helper package
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/ec2"
	"github.com/aws/aws-sdk-go-v2/service/ec2/types" // ADDED: Import for the 'types' package
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/require"
)

// NOTE: The getRequiredEnvVar helper is not needed as variables are passed
// directly from the CI workflow using the TF_VAR_ convention.

func TestStorageModuleWithRAID(t *testing.T) {
	t.Parallel()

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
		// Capture the test case variables to use them in the sub-test
		tc := tc
		t.Run(testName, func(t *testing.T) {
			t.Parallel()

			// Terratest will automatically use any TF_VAR_ environment variables
			// set in the GitHub Actions workflow.
			terraformOptions := &terraform.Options{
				TerraformDir:    "../modules/storage_servers/examples",
				TerraformBinary: "terraform",
				// Pass test-specific variables
				Vars: map[string]interface{}{
					"project_name":           fmt.Sprintf("terratest-storage-%s-%s", tc.raidLevel, random.UniqueId()),
					"storage_instance_count": 1,
					"storage_ebs_count":      tc.diskCount,
					"storage_raid_level":     tc.raidLevel,
				},
			}

			defer terraform.Destroy(t, terraformOptions)
			terraform.InitAndApply(t, terraformOptions)

			// --- Validation ---
			awsRegion := terraform.Output(t, terraformOptions, "region")
			storageInstances := terraform.OutputListOfObjects(t, terraformOptions, "storage_instances")
			require.Len(t, storageInstances, 1, "Expected to find 1 storage instance")

			instanceID := storageInstances[0]["id"].(string)

			// --- Use AWS SDK to validate the attached volumes ---
			cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion(awsRegion))
			require.NoError(t, err, "Failed to load AWS configuration")
			ec2Client := ec2.NewFromConfig(cfg)

			describeVolumesInput := &ec2.DescribeVolumesInput{
				Filters: []types.Filter{
					{
						// MODIFIED: Use the correct aws.String() helper
						Name:   aws.String("attachment.instance-id"),
						Values: []string{instanceID},
					},
				},
			}
			describeVolumesOutput, err := ec2Client.DescribeVolumes(context.TODO(), describeVolumesInput)
			require.NoError(t, err, "Failed to describe EBS volumes")

			// Validate the volume count: 1 boot disk + the number of disks for RAID.
			expectedTotalVols := 1 + tc.diskCount
			require.Len(t, describeVolumesOutput.Volumes, expectedTotalVols, "Incorrect number of EBS volumes attached to instance %s", instanceID)

			t.Logf("Successfully validated creation of %d total volumes for %s test.", expectedTotalVols, testName)
		})
	}
}
