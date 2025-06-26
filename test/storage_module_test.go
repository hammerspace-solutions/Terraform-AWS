package test

import (
	"fmt"
	"os"
	"testing"

	"github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/require"
)

// TestStorageModuleWithRAID runs a suite of integration tests for the storage_servers module,
// covering different RAID levels.
func TestStorageModuleWithRAID(t *testing.T) {
	// --- Test Setup: Read shared variables from the environment once ---
	// These are the same for all sub-tests.
	awsRegion := getRequiredEnvVar(t, "REGION")
	vpcId := getRequiredEnvVar(t, "VPC_ID")
	subnetId := getRequiredEnvVar(t, "SUBNET_ID")
	keyName := getRequiredEnvVar(t, "KEY_NAME")
	storageAmi := getRequiredEnvVar(t, "STORAGE_AMI")

	// Define the test cases for each RAID level.
	// We use a map where the key is the test name and the value contains test-specific settings.
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
			diskCount:    3,          // Minimum for RAID-5
			instanceType: "t3.large", // Use a different instance type just to show variation
		},
		"RAID-6": {
			raidLevel:    "raid-6",
			diskCount:    4, // Minimum for RAID-6
			instanceType: "t3.medium",
		},
	}

	// --- Run Sub-Tests ---
	// Iterate over the test cases and run each one as a parallel sub-test.
	for testName, tc := range testCases {
		// The `t.Run` function creates a sub-test. This is a Go standard library feature.
		// It allows us to run isolated tests within the same parent test function.
		t.Run(testName, func(t *testing.T) {
			t.Parallel() // Mark this sub-test as safe to run in parallel.

			projectName := fmt.Sprintf("terratest-storage-%s-%s", tc.raidLevel, random.UniqueId())

			// Configure the Terraform options specifically for this sub-test.
			terraformOptions := &terraform.Options{
				TerraformDir:    "../modules/storage_servers/examples",
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
					"storage_user_data":	  "../../../templates/storage_server_ubuntu.sh",
				},
			}

			// Defer the destroy to ensure cleanup happens for this sub-test.
			defer terraform.Destroy(t, terraformOptions)

			// Apply the infrastructure.
			terraform.InitAndApply(t, terraformOptions)

			// --- Validation ---
			// 1. Check that the correct number of instances were created.
			storageInstances := terraform.OutputListOfObjects(t, terraformOptions, "storage_instances")
			require.Equal(t, 1, len(storageInstances), "Expected to find 1 storage instance")

			instanceID := storageInstances[0]["id"].(string)

			// 2. Describe the volumes attached to the instance.
			instanceVols := aws.GetEbsVolumesForInstance(t, awsRegion, instanceID)

			// 3. Validate the volume count.
			// We expect 1 boot disk + the number of disks we specified for the RAID array.
			expectedTotalVols := 1 + tc.diskCount
			require.Equal(t, expectedTotalVols, len(instanceVols), "Incorrect number of EBS volumes attached to instance %s", instanceID)

			// This is where you would add a more advanced test. For example, you could
			// use the `terratest/modules/ssh` package to connect to the instance and
			// run `cat /proc/mdstat` to verify that the `/dev/md0` RAID device is active
			// and contains the correct number of disks. This would be the ultimate validation.
			t.Logf("Successfully validated creation of %d total volumes for %s test.", expectedTotalVols, testName)
		})
	}
}
