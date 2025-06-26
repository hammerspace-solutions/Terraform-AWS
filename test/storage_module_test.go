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
	"github.com/gruntwork-io/terratest/modules/retry"
	"github.com/gruntwork-io/terratest/modules/ssh"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/stretchr/testify/require"
)

// NOTE: The getRequiredEnvVar helper function is located in test_helpers.go

func TestStorageModuleWithRAID(t *testing.T) {
	t.Parallel()

	// --- Test Setup: Read shared variables & generate SSH key ---
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
		instanceType string
	}{
		"RAID-0": {
			raidLevel:    "raid-0",
			diskCount:    2,
			instanceType: "t3.medium",
		},
		"RAID-5": {
			raidLevel:    "raid-5",
			diskCount:    3,
			instanceType: "t3.large",
		},
		"RAID-6": {
			raidLevel:    "raid-6",
			diskCount:    4,
			instanceType: "t3.medium",
		},
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
					"storage_instance_type":  tc.instanceType,
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

			// Patiently wait for the instance to reboot and the RAID array to be ready.
			maxRetries := 40
			sleepBetweenRetries := 15 * time.Second
			description := fmt.Sprintf("SSH to instance %s and check mdstat", publicIp)

			var mdstatOutput string
			retry.DoWithRetry(t, description, maxRetries, sleepBetweenRetries, func() (string, error) {
				// --- THIS IS THE FIX ---
				// The correct function name is RunSshCommandAndGetOutputE
				output, err := ssh.RunSshCommandAndGetOutputE(t, host, "cat /proc/mdstat")
				if err != nil {
					return "", err
				}
				mdstatOutput = output
				return "Successfully connected and ran command.", nil
			})

			// --- Deep Validation of RAID Array via SSH ---
			require.Contains(t, mdstatOutput, "md0 : active", "RAID device md0 is not active")
			require.Contains(t, mdstatOutput, tc.raidLevel, "Incorrect RAID level found in mdstat output")

			re := regexp.MustCompile(`\[(\d+)/\d+\]`)
			matches := re.FindStringSubmatch(mdstatOutput)
			require.Len(t, matches, 2, "Could not parse number of disks from mdstat output")

			activeDisksStr := matches[1]
			activeDisks, err := strconv.Atoi(activeDisksStr)
			require.NoError(t, err, "Could not convert active disk count to integer")

			require.Equal(t, tc.diskCount, activeDisks, "Incorrect number of active disks in the RAID array")
			t.Logf("Successfully validated RAID level %s with %d disks on instance %s.", tc.raidLevel, activeDisks, publicIp)

			// --- Final Validation of EBS Volumes via AWS SDK ---
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
