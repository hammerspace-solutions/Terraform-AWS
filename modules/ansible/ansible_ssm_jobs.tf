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
# modules/ansible/ansible_ssm_jobs.tf
#
# This file contains the logic to discover and push Ansible job files from the
# local 'ansible_job_files' directory to the Ansible instance via SSM.
# -----------------------------------------------------------------------------

# --- Discover Local Job Files ---
locals {
  # Find all executable shell scripts in the specified job files directory.
  # The result is a set of relative file paths (e.g., {"10-setup.sh", "20-configure.sh"}).
  ansible_job_files = fileset("${path.module}/ansible_job_files", "*.sh")
}

# --- SSM Document for Writing Files ---
# A generic SSM document that takes content and writes it to a specified file path.
resource "aws_ssm_document" "ansible_write_job_file" {
  name          = "${local.resource_prefix}-write-file"
  document_type = "Command"
  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Writes Base64 encoded content to a specific file on the instance."
    parameters = {
      FileName          = { type = "String", description = "The name of the file to create." }
      FileContentBase64 = { type = "String", description = "The Base64 encoded content of the file." }
      TargetPath        = { type = "String", description = "The absolute path of the target directory." }
      FilePermissions   = { type = "String", description = "The file permissions (e.g., 0755)." }
    }
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "WriteFile"
      inputs = {
        runCommand = [
          "set -e",
          "TARGET_DIR={{ TargetPath }}",
          "FILE_NAME={{ FileName }}",
          "TARGET_FILE=\"$${TARGET_DIR}/$${FILE_NAME}\"",
          "echo 'Writing file to $${TARGET_FILE}...'",
          "# Ensure the target directory exists.",
          "mkdir -p \"$${TARGET_DIR}\"",
          "# Decode the content and write it to the target file.",
          "echo {{ FileContentBase64 }} | base64 -d > \"$${TARGET_FILE}\"",
          "# Set the specified permissions on the file.",
          "chmod {{ FilePermissions }} \"$${TARGET_FILE}\"",
          "echo 'File successfully written and permissions set.'"
        ]
      }
    }]
  })
}

# --- SSM Association to Push Each Job File ---
# This resource loops through each discovered job file and creates a dedicated
# SSM association to push it to the Ansible instance.
resource "aws_ssm_association" "ansible_push_job_files" {
  # Create one association for each file found in the 'ansible_job_files' set.
  for_each = local.ansible_job_files

  # The association name must be unique. We use the filename to ensure this.
  # We replace '.' with '-' in the filename to create a valid association name.
  association_name = "Push-Job-File-${replace(each.key, ".", "-")}-${aws_instance.ansible[0].id}"
  name             = aws_ssm_document.ansible_write_job_file.name

  targets {
    key    = "InstanceIds"
    values = [aws_instance.ansible[0].id]
  }

  parameters = {
    TargetPath        = "/usr/local/ansible/jobs"
    FileName          = each.key
    FileContentBase64 = filebase64("${path.module}/ansible_job_files/${each.key}")
    FilePermissions   = "0755" # Executable permissions for job scripts.
  }

  # THIS IS THE CRITICAL DEPENDENCY:
  # This ensures that we do not attempt to push any job files until the SSM agent
  # has been confirmed to be online by our robust polling mechanism.
  depends_on = [
    null_resource.wait_for_ssm_agent_polling
  ]
}
