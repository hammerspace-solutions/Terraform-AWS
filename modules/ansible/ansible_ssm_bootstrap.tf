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
# modules/ansible/ansible_ssm_bootstrap.tf
#
# This file contains the SSM resources for bootstrapping the Ansible instance.
# -----------------------------------------------------------------------------

# Wait for SSM agent to come online before creating the association
resource "time_sleep" "wait_for_ssm_agent" {
  count           = var.use_ssm_bootstrap ? 1 : 0
  create_duration = var.ssm_bootstrap_delay
  depends_on      = [aws_instance.ansible]
}

# Create SSM document for bootstrapping (idempotent, safe to re-run)
resource "aws_ssm_document" "ansible_bootstrap" {
  count         = var.use_ssm_bootstrap ? 1 : 0
  name          = "${local.resource_prefix}-ansible-bootstrap"
  document_type = "Command"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Bootstrap the Ansible host: install controller + authorized_keys (via SSM)"
    parameters = {
      TargetUser    = { type = "String", description = "Linux user to receive authorized_keys (in addition to root)" }
      AuthorizedB64 = { type = "String", description = "Base64 authorized_keys content" }
      FunctionsB64  = { type = "String", description = "Base64 functions script" }
      DaemonB64     = { type = "String", description = "Base64 daemon script" }
      UnitB64       = { type = "String", description = "Base64 systemd unit" }
    }
    mainSteps = [{
      name   = "BootstrapAnsibleHost"
      action = "aws:runShellScript"
      inputs = {
        runCommand = [
          "# --- idempotency guard: skip install if files already present ---",
          "if [ -f /usr/local/bin/ansible_controller_daemon.sh ] && systemctl list-unit-files | grep -q '^ansible-controller.service'; then",
          "  SKIP_INSTALL=1",
          "else",
          "  SKIP_INSTALL=0",
          "fi",

          "# --- helper: append + dedupe authorized_keys ---",
          "append_auth_keys() { target=\"$1\"; tmp=\"/tmp/authorized_keys.$$\"; umask 077; echo {{ AuthorizedB64 }} | base64 -d > \"$tmp\" || true; sed -i 's/\\r$//' \"$tmp\" 2>/dev/null || true; touch \"$target\" && chmod 600 \"$target\"; while IFS= read -r line; do [ -z \"$line\" ] && continue; case \"$line\" in \\#*) continue ;; esac; grep -qxF \"$line\" \"$target\" || echo \"$line\" >> \"$target\"; done < \"$tmp\"; rm -f \"$tmp\"; }",

          "# --- always: root keys ---",
          "install -d -m 0700 /root/.ssh",
          "append_auth_keys /root/.ssh/authorized_keys",

          "# --- also: target user keys unless root ---",
          "U='{{ TargetUser }}'",
          "if [ \"$U\" != \"root\" ]; then",
          "  HOME_DIR=$(getent passwd \"$U\" | cut -d: -f6 || echo \"/home/$U\")",
          "  install -d -m 0700 \"$HOME_DIR/.ssh\"",
          "  append_auth_keys \"$HOME_DIR/.ssh/authorized_keys\"",
          "  chown -R \"$U\":\"$U\" \"$HOME_DIR/.ssh\"",
          "fi",

	  "# --- Create all necessary directories BEFORE starting the service ---",
	  "install -d -m 0755 /var/ansible/trigger /usr/local/ansible/jobs /var/run/ansible_jobs_status /etc/ansible",
	  
          "# --- install controller files only if not present ---",
          "if [ \"$SKIP_INSTALL\" -eq 0 ]; then",
          "  echo {{ FunctionsB64 }} | base64 -d > /usr/local/lib/ansible_functions.sh",
          "  chmod 0644 /usr/local/lib/ansible_functions.sh",

          "  echo {{ DaemonB64 }} | base64 -d > /usr/local/bin/ansible_controller_daemon.sh",
          "  chmod 0755 /usr/local/bin/ansible_controller_daemon.sh",

          "  echo {{ UnitB64 }} | base64 -d > /etc/systemd/system/ansible-controller.service",
          "fi",

          "# --- systemd ---",
          "systemctl daemon-reload",
          "systemctl enable --now ansible-controller.service"
        ]
      }
    }]
  })
}

# Associate the ssm document with all instances (retry via schedule; no CLI)
resource "aws_ssm_association" "ansible_bootstrap" {
  count = (var.use_ssm_bootstrap ? var.instance_count : 0)

  name = aws_ssm_document.ansible_bootstrap[0].name

  targets {
    key    = "InstanceIds"
    values = [aws_instance.ansible[count.index].id]
  }

  # Retry via State Manager schedule (runs now and per schedule)
  schedule_expression = (
    var.ssm_association_schedule != null && var.ssm_association_schedule != ""
    ? var.ssm_association_schedule
    : null
  )

  parameters = {
    TargetUser    = var.target_user
    AuthorizedB64 = local.authorized_keys_b64
    FunctionsB64  = local.functions_b64
    DaemonB64     = local.daemon_b64
    UnitB64       = local.controller_unit_b64
  }

  depends_on = [
    aws_instance.ansible,
    time_sleep.wait_for_ssm_agent
  ]
}
