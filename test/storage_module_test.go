package test

import (
	"context"
	"fmt"
	"path/filepath"
	"regexp"
	"strconv"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/ec2"
	"github.com/aws/aws-sdk-go-v2/service/ec2/types"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/retry" // Import the retry module
	"github.com/gruntwork-io/terratest/modules/ssh"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/stretchr/testify/require"
)

// NOTE: The getRequiredEnvVar helper function is located in test_helpers.go

func TestStorageModuleWithRAID(t *testing.T) {
	t.Parallel()

	// --- Test Setup ---
	awsRegion := getRequiredEnvVar(t, "REGION")
	vpcId := getRequiredEnvVar(t, "VPC_ID")
	subnetId := getRequiredEnvVar(t, "SUBNET_ID")
	storageAmi := getRequiredEnvVar(t, "STORAGE_AMI")

	sshKeyPair := ssh.GenerateRSAKeyPair(t, 2048)

	projectRoot, err := filepath.Abs("../")
	require.NoError(t, err, "Failed to get project root path")
	userDataScriptPath := filepath.Join(projectRoot, "templates", "storage_server_ubuntu.sh")

	testCases := map[string]struct {
		raidLevel    string
		diskCount    int
	}{
		"RAID-0": {raidLevel: "raid-0", diskCount: 2},
		"RAID-5": {raidLevel: "raid-5", diskCount: 3},
		"RAID-6": {raidLevel: "raid-6", diskCount: 4},
	}

	for testName, tc := range testCases {
		tc := tc
		t.Run(testName, func(t *testing.T) {
			t.Parallel()

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
					"storage_ami":            storageAmi,
					"ssh_public_key":         sshKeyPair.PublicKey,
					"storage_instance_count": 1,
					"storage_ebs_count":      tc.diskCount,
					"storage_raid_level":     tc.raidLevel,
					"storage_user_data":      userDataScriptPath,
				},
			}

			defer terraform.Destroy(t, terraformOptions)
			terraform.InitAndApply(t, terraformOptions)

			// --- Validation ---
			publicIp := terraform.Output(t, terraformOptions, "public_ip")
			require.NotEmpty(t, publicIp, "Instance public IP should not be empty")

			host := ssh.Host{
				Hostname:    publicIp,
				SshKeyPair:  sshKeyPair,
				SshUserName: "ubuntu",
			}
			
			// --- THIS IS THE FIX ---
			// The user_data script reboots the instance, so we can't just check for an
			// SSH connection once. Instead, we use a retry loop to repeatedly run our
			// validation command until it succeeds or we time out. This gracefully
			// handles the reboot.
			maxRetries := 40
			sleepBetweenRetries := 15 * time.Second
			description := fmt.Sprintf("SSH to instance %s and check mdstat", publicIp)

			var mdstatOutput string // Declare a variable to store the command output

			retry.DoWithRetry(t, description, maxRetries, sleepBetweenRetries, func() (string, error) {
				// Try to run the command via SSH.
				output, err := ssh.RunSshCommandE(t, host, "cat /proc/mdstat")
				if err != nil {
					return "", err // If it fails (e.g., connection refused), return the error to trigger a retry.
				}
				
				// If the command succeeds, store the output and return nil to stop retrying.
				mdstatOutput = output
				return "Successfully connected and ran command.", nil
			})
			

			// --- Deep Validation of RAID Array ---
			// Now that we have the output, we can proceed with the same validation logic.
			require.Contains(t, mdstatOutput, "md0 : active", "RAID device md0 is not active")
			require.Contains(t, mdstatOutput, tc.raidLevel, "Incorrect RAID level found in mdstat output")

			re := regexp.MustCompile(`\[(\d+)/\d+\]`)
			matches := re.FindStringSubmatch(mdstatOutput)
			require.Len(t, matches, 2, "Could not parse number of disks from mdstat output")
			
			activeDisksStr := matches[1]
			activeDisks, err := strconv.Atoi(activeDisksStr)
			require.NoError(t, err, "Could not convert active disk count to integer")

			require.Equal(t, tc.diskCount, activeDisks, "Incorrect number of active disks in the RAID array")
			
			t.Logf("Successfully validated RAID level %s with %d disks on instance %s.", tc.raidLevel, tc.diskCount, publicIp)
		})
	}
}
