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
	"github.com/stretchr/testify/require"
)

// NOTE: The getRequiredEnvVar helper function is located in test_helpers.go
// and is available to all tests in this package.

func TestStorageModuleWithRAID(t *testing.T) {
	t.Parallel()

	// --- Test Setup: Read shared variables from the environment once ---
	// These are the same for all sub-tests.
	awsRegion := getRequiredEnvVar(t, "REGION")
	vpcId := getRequiredEnvVar(t, "VPC_ID")
	subnetId := getRequiredEnvVar(t, "SUBNET_ID")
	keyName := getRequiredEnvVar(t, "KEY_NAME")
	storageAmi := getRequiredEnvVar(t, "STORAGE_AMI")

	// Define the test cases for each RAID level.
	testCases := map[string]struct {
		raidLevel    string
		diskCount    int
		instanceType string
	}{
		"RAID-0": {
			raidLevel:    "raid-0",
			diskCount:    2, // Minimum for RAID-0
			instanceType: "t3.medium",
		},
		"RAID-5": {
			raidLevel:    "raid-5",
			diskCount:    3, // Minimum for RAID-5
			instanceType: "t3.large",
		},
		"RAID-6": {
			raidLevel:    "raid-6",
			diskCount:    4, // Minimum for RAID-6
			instanceType: "t3.medium",
		},
	}

	for testName, tc := range testCases {
		// Capture range variable for parallel tests
		tc := tc
		t.Run(testName, func(t *testing.T) {
			t.Parallel()

			// Copy the 'examples' folder to a temporary, isolated directory for this test run.
			tempTestFolder := test_structure.CopyTerraformFolderToTemp(t, "../modules/storage_servers", "examples")

			projectName := fmt.Sprintf("terratest-storage-%s-%s", tc.raidLevel, random.UniqueId())

			terraformOptions := &terraform.Options{
				TerraformDir:    tempTestFolder,
				TerraformBinary: "terraform",
				Vars: map[string]interface{}{
					"project_name":           projectName,
					"region":                 awsRegion,
					"vpc_id":                 vpcId,
					"subnet_id":              subnetId,
					"key_name":               keyName,
					"storage_ami":            storageAmi,
					"storage_instance_type":  tc.instanceType,
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

			// --- Use AWS SDK to validate the attached volumes ---
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

			// Validate the volume count: 1 boot disk + the number of disks for RAID.
			expectedTotalVols := 1 + tc.diskCount
			require.Len(t, describeVolumesOutput.Volumes, expectedTotalVols, "Incorrect number of EBS volumes attached to instance %s", instanceID)

			t.Logf("Successfully validated creation of %d total volumes for %s test.", expectedTotalVols, testName)
		})
	}
}
