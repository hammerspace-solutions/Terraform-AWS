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
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

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
	
	// Define expected values for validation
	expectedInstanceCount := 1
	expectedEbsCount := 2 
	expectedBootVolumeType := "gp3"
	expectedEbsVolumeType := "gp3"

	terraformOptions := &terraform.Options{
		TerraformDir:    "../modules/clients/tests",
		TerraformBinary: "terraform",
		Vars: map[string]interface{}{
			"project_name":           projectName,
			"region":                 awsRegion,
			"vpc_id":                 vpcId,
			"subnet_id":              subnetId,
			"key_name":               keyName,
			"clients_ami":            clientsAmi,
			"clients_instance_count": expectedInstanceCount,
			"ebs_count":              expectedEbsCount,
			"boot_volume_type":       expectedBootVolumeType,
			"ebs_type":               expectedEbsVolumeType,
		},
	}

	// --- Test Lifecycle ---
	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// --- Validation ---
	clientInstances := terraform.OutputListOfObjects(t, terraformOptions, "client_instances")
	require.Equal(t, expectedInstanceCount, len(clientInstances), "Expected to find %d client instance in the output", expectedInstanceCount)
	
	instanceID := clientInstances[0]["id"].(string)

	// --- AWS SDK Validation: Check Instance and Volume Details ---
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion(awsRegion))
	require.NoError(t, err, "Failed to load AWS configuration")
	ec2Client := ec2.NewFromConfig(cfg)

	// 1. Describe the instance to find its root device name
	describeInstancesInput := &ec2.DescribeInstancesInput{
		InstanceIds: []string{instanceID},
	}
	describeInstancesOutput, err := ec2Client.DescribeInstances(context.TODO(), describeInstancesInput)
	require.NoError(t, err, "Failed to describe EC2 instance")
	require.Len(t, describeInstancesOutput.Reservations, 1, "Expected 1 reservation")
	require.Len(t, describeInstancesOutput.Reservations[0].Instances, 1, "Expected 1 instance in reservation")
	
	instanceFromApi := describeInstancesOutput.Reservations[0].Instances[0]
	rootDeviceName := *instanceFromApi.RootDeviceName
	assert.Equal(t, types.InstanceStateNameRunning, instanceFromApi.State.Name, "Instance is not in 'running' state")


	// 2. Describe all volumes attached to the instance
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

	// 3. Assert the total number of volumes is correct (1 root + expectedEbsCount)
	totalExpectedVolumes := 1 + expectedEbsCount
	assert.Len(t, describeVolumesOutput.Volumes, totalExpectedVolumes, "Incorrect number of total volumes attached")

	// 4. Iterate through the attached volumes and validate each one
	foundRootVolume := false
	extraVolumesCount := 0
	for _, volume := range describeVolumesOutput.Volumes {
		require.Len(t, volume.Attachments, 1, "Expected volume to have one attachment")
		deviceName := *volume.Attachments[0].Device

		if deviceName == rootDeviceName {
			foundRootVolume = true
			fmt.Printf("Validating root volume (%s) at %s\n", *volume.VolumeId, deviceName)
			assert.Equal(t, types.VolumeType(expectedBootVolumeType), volume.VolumeType, "Root volume has incorrect type")
		} else {
			extraVolumesCount++
			fmt.Printf("Validating extra EBS volume (%s) at %s\n", *volume.VolumeId, deviceName)
			assert.Equal(t, types.VolumeType(expectedEbsVolumeType), volume.VolumeType, "Extra EBS volume has incorrect type")
		}
	}

	assert.True(t, foundRootVolume, "Test failed to find the root volume")
	assert.Equal(t, expectedEbsCount, extraVolumesCount, "Incorrect number of extra EBS volumes found")
}

