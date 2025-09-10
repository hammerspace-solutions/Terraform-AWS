# Copyright (c) 2025 Hammerspace, Inc
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# -----------------------------------------------------------------------------
# modules/ansible/ansible_ssm_wait.tf
#
# This file contains the logic to robustly wait for the SSM agent on the
# Ansible instance to come online using a polling mechanism.
# -----------------------------------------------------------------------------

# --- Pre-flight Check for AWS CLI ---
# This check runs during the 'plan' phase to ensure the AWS CLI is installed
# on the machine running Terraform, as it's a prerequisite for the polling provisioner.
check "aws_cli_is_installed" {
  data "external" "aws_cli_check" {
    # Using 'type' is a highly reliable, shell-builtin way to check for a command.
    program = ["bash", "-c", "if type aws >/dev/null 2>&1; then echo '{\"found\": \"true\"}'; else echo '{\"found\": \"false\"}'; fi"]
  }

  assert {
    condition     = data.external.aws_cli_check.result.found == "true"
    error_message = "Prerequisite Failure: The AWS CLI is not installed or not found in the system's PATH. The polling mechanism for the SSM agent requires the AWS CLI to be installed on the machine running 'terraform apply'. Please install it and ensure it is accessible in your PATH before proceeding."
  }
}

# --- SSM Agent Polling Resource ---
resource "null_resource" "wait_for_ssm_agent_polling" {
  count = var.use_ssm_bootstrap ? var.instance_count : 0

  triggers = {
    # This trigger ensures the provisioner runs whenever the instance ID changes.
    instance_id = aws_instance.ansible[count.index].id
  }

  # This provisioner runs a script on the machine that is executing 'terraform apply'.
  # It is the only way to perform a procedural polling loop.
  # Prerequisite: The machine running Terraform must have the AWS CLI installed and configured.
  provisioner "local-exec" {
    command = <<-EOT
      # These Terraform variables are interpolated directly by Terraform.
      retries=${var.ssm_bootstrap_retries}
      interval_sec=${replace(var.ssm_bootstrap_delay, "s", "")}
      instance_id="${aws_instance.ansible[count.index].id}"
      region="${var.common_config.region}"

      echo "Waiting for SSM agent on instance $${instance_id} in region $${region} to come online..."

      # Use a portable POSIX-compliant 'while' loop.
      # All shell variables are escaped with '$${...}' to prevent Terraform interpolation.
      i=1
      while [ $${i} -le $${retries} ]; do
        echo "Polling for SSM status... Attempt $${i} of $${retries}..."

        # This is the robust check: get the full JSON output and use grep to look for the "Online" status.
        # We now explicitly pass the --region flag to ensure we query the correct endpoint.
        if aws ssm describe-instance-information --region $${region} --instance-information-filter-list key=InstanceIds,valueSet=$${instance_id} | grep -q '"PingStatus": "Online"'; then
          echo "SSM agent is Online. Proceeding successfully."
          exit 0
        fi

        if [ $${i} -lt $${retries} ]; then
          echo "Agent is not yet online. Waiting for $${interval_sec} seconds before retrying..."
          sleep $${interval_sec}
        fi

        # Use the universally portable 'expr' command for arithmetic.
        i=`expr $${i} + 1`
      done

      echo "Error: SSM agent on instance $${instance_id} did not come online after $${retries} attempts."
      echo "Please check the instance's network connectivity and IAM permissions."
      exit 1
    EOT
  }
}

