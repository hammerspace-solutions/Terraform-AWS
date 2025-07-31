#!/bin/bash

# Main control script for the Ansible controller.
# Discovers, sorts, and executes job scripts, tracking their status.

set -euo pipefail

# --- Configuration ---
ANSIBLE_LIB_PATH="/usr/local/lib/ansible_functions.sh"
CONFIG_DIR="/tmp/ansible_config"
PROCESSED_DIR="/tmp/ansible_config/processed"
FAILED_DIR="/tmp/ansible_config/failed"
STATUS_DIR="/var/run/ansible_jobs_status"
LOCK_FILE="/var/ansible_initial_setup.done"
CHECK_INTERVAL=30 # Seconds

# --- Source the function library ---
if [ -f "$ANSIBLE_LIB_PATH" ]; then
    source "$ANSIBLE_LIB_PATH"
else
    echo "FATAL: Function library not found at $ANSIBLE_LIB_PATH" >&2
    exit 1
fi

# --- Main Logic ---

# 1. Run the one-time initial setup if it hasn't been done before.
if [ ! -f "$LOCK_FILE" ]; then
    echo "--- Running Initial First-Time Setup ---"
    run_initial_setup
    echo "--- Initial Setup Complete ---"
else
    echo "Initial setup already completed. Starting job watch."
fi

# 2. Create necessary directories
mkdir -p "$PROCESSED_DIR" "$FAILED_DIR" "$STATUS_DIR"

# 3. Start the main loop to watch for new job scripts.
echo "--- Watching for new job scripts in $CONFIG_DIR ---"
while true; do
    # Find all executable shell scripts, sort them numerically
    job_scripts=$(find "$CONFIG_DIR" -maxdepth 1 -type f -name "*.sh" | sort -n)

    if [ -n "$job_scripts" ]; then
        for script_path in $job_scripts; do
            script_name=$(basename "$script_path")
            echo "--- Discovered job: $script_name ---"

            # Execute the job script
            if bash "$script_path"; then
                # On success, record it and move the script
                echo "SUCCESS" > "$STATUS_DIR/$script_name.success"
                echo "Job $script_name completed successfully."
                mv "$script_path" "$PROCESSED_DIR/"
            else
                # On failure, record it and move the script to the failed directory
                echo "FAILURE" > "$STATUS_DIR/$script_name.failure"
                echo "ERROR: Job $script_name failed. See logs for details. Moving to failed directory."
                mv "$script_path" "$FAILED_DIR/"
            fi
            echo "--- Finished job: $script_name ---"
        done
    fi

    sleep "$CHECK_INTERVAL"
done
