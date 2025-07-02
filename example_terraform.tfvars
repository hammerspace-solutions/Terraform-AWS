# Timeout value if resources are not available in your
# availability zone. This default is a "short" 3 minutes

capacity_reservation_create_timeout  = "3m"

# Which components to deploy
#
# Valid answers are "clients", "storage", "hammerspace", or "all". The
# structure is a list, so you can say "storage", "hammerspace" to deploy
# both of those

deploy_components		     = ["all"]

# Set this variable is you want public ip addresses for each of the instances.
# Otherwise, only private ip addresses will be assigned.

assign_public_ip  	     	     = false

# Custom AMI owner ID's
# This is a list of the owners of any custom AMI's. Since Hammerspace is a custom AMI,
# in order to provide guard-rail checking if the AMI exists in a given region, we will
# need to specify the AMI owner. In this case, Hammerspace and Ubuntu owners...

custom_ami_owner_ids  	  	     = ["919243021404", "679593333241"]

# Placement Group
#
# Leave the name blank if you don't want your resources in a placement group
# Use a name to create a new group

placement_group_name		     = "Terraform-Group"
placement_group_strategy	     = "cluster"

# Global variables
#
# Change your project_name, the key_name, and the vpc and subnet id's

project_name		             = "AWS-Project"
key_name   			     = "Some-PEM-Key"
vpc_id     			     = "vpc-e3b5890"
subnet_id  			     = "subnet-0d8a5034456df"

# You can put in as many tags as you would like. The format should be self-explanatory

tags = {
  Owner				     = "Terraform Owner"
  Project 			     = "Terraform Testing"
}

# Client specific variables (clients_ prefix)
#
# The only thing that might be confusing are the variables:
# "clients_user_data" and "clients_target_user". In AWS, the login
# to a EC2 instance is usually of the form:
# "ssh -i PEM_FILE OS_NAME@IP_ADDRESS"
#
# So, the clients_target_user is the OS_NAME for the login. Once you
# have logged in once, you can create as many users as you want. But,
# that first default user is the OS_NAME (or in this case "ubuntu"
#
# The clients_user_data is a location where a bash shell script is stored.
# You can modify that script as it is passed to the EC2 instance during
# instantiation. It can be used for further configuration. Remember that
# the script MUST conform to the OS that you are instantiating. Today,
# we only have scripts for ubuntu and rocky.

clients_instance_count		     = 2
clients_ami 			     = "ami-04cfeb9ad57f3053a"
clients_instance_type 		     = "m5n.2xlarge"
clients_boot_volume_size	     = 100
clients_boot_volume_type	     = "gp2"
clients_ebs_count 		     = 0
clients_ebs_size  		     = 1000
clients_ebs_type  		     = "gp3"
clients_ebs_iops  		     = 9000
clients_ebs_throughput	 	     = 1000
clients_user_data 		     = "./templates/client_config_ubuntu.sh"
clients_target_user 		     = "ubuntu"

# Storage specific variables (storage_ prefix)
#
# The only thing that might be confusing are the variables:
# "clients_user_data" and "clients_target_user". In AWS, the login
# to a EC2 instance is usually of the form:
# "ssh -i PEM_FILE OS_NAME@IP_ADDRESS"
#
# So, the clients_target_user is the OS_NAME for the login. Once you
# have logged in once, you can create as many users as you want. But,
# that first default user is the OS_NAME (or in this case "ubuntu"
#
# The clients_user_data is a location where a bash shell script is stored.
# You can modify that script as it is passed to the EC2 instance during
# instantiation. It can be used for further configuration. Remember that
# the script MUST conform to the OS that you are instantiating. Today,
# we only have scripts for ubuntu and rocky.

storage_instance_count	 	     = 5
storage_ami 			     = "ami-04cfeb9ad57f3053a"
storage_instance_type 		     = "m5n.2xlarge"
storage_boot_volume_size	     = 100
storage_boot_volume_type	     = "gp2"
storage_raid_level		     = "raid-6"
storage_ebs_count 		     = 6
storage_ebs_size  		     = 1000
storage_ebs_type  		     = "gp3"
storage_ebs_iops  		     = 9000
storage_ebs_throughput	 	     = 1000
storage_user_data 		     = "./templates/storage_server_ubuntu.sh"
storage_target_user 		     = "ubuntu"

# Hammerspace (Anvil, DSX) specific variables

hammerspace_ami			     = "ami-094d8e62982f34834"

# --- Optional: Provide existing Security Group IDs for debugging ---
# hammerspace_anvil_security_group_id  = "sg-0f888587d7e83bda2"
# hammerspace_dsx_security_group_id    = "sg-0f888587d7e83bda2"

# If you do not have permissions in your AWS environment to create roles
# and permissions, then enter the name of a predefined role with appropriate
# permissions in the hammerspace_profile_id variable. If you have the capability
# to create a role, then comment out that variable

# hammerspace_profile_id	       = "Hammerspace"

# Anvil specific

hammerspace_anvil_count		     = 2
hammerspace_sa_anvil_destruction     = true
hammerspace_anvil_instance_type      = "m5n.2xlarge"
hammerspace_anvil_meta_disk_size     = 1000
hammerspace_anvil_meta_disk_type     = "gp3"
hammerspace_anvil_meta_disk_iops     = 9000
hammerspace_anvil_meta_disk_throughput = 1000

# DSX specific

hammerspace_dsx_count                = 1
hammerspace_dsx_instance_type 	     = "m5n.2xlarge"
hammerspace_dsx_ebs_count	     = 5
hammerspace_dsx_ebs_size 	     = 1000
hammerspace_dsx_ebs_type	     = "gp3"
hammerspace_dsx_ebs_iops	     = 6000
hammerspace_dsx_ebs_throughput	     = 1000

# Ansible specific variables (ansible_ prefix)
#
# The only thing that might be confusing are the variables:
# "ansible_user_data" and "ansible_target_user". In AWS, the login
# to a EC2 instance is usually of the form:
# "ssh -i PEM_FILE OS_NAME@IP_ADDRESS
#
# So, the ansible_target_user is the OS_NAME for the login. Once you
# have logged in once, you can create as many users as you want. But,
# the first default user is the OS_NAME (or in this case "ubuntu")
#
# The ansible_user_data is a location where a bash shell script is stored.
# You can modify that script as it is passed to the EC2 instance during
# instantiation. It can be used for further configuration. Remember that
# the script MUST conform to the OS that you are instantiating. Today,
# we only have a script for ubuntu.

ansible_instance_count		     = 1
ansible_ami			     = "ami-04cfeb9ad57f3053a"
ansible_instance_type		     = "m5n.2xlarge"
ansible_boot_volume_size	     = 40
ansible_boot_volume_type	     = "gp2"
ansible_user_data		     = "./templates/ansible_config_ubuntu.sh"
ansible_target_user		     = "ubuntu"
volume_group_name		     = "vg_auto"
share_name			     = "test01"
