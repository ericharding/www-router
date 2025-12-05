#!/bin/bash
set -euo pipefail

# Script to completely remove a project
# Usage: ./destroy.sh <project_slug>
# Example: ./destroy.sh proj1
#
# This script will:
# - Stop and disable the systemd service
# - Disable user linger
# - Delete the user and home directory (including podman images)

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Check if script is run with sudo
require_sudo

# Parse arguments
if [ $# -ne 1 ]; then
    log_error "Usage: $0 <project_slug>"
    log_error "Example: $0 proj1"
    exit 1
fi

PROJECT_SLUG="$1"

# Check if user exists
check_user_exists "$PROJECT_SLUG"

log_warn "=========================================="
log_warn "WARNING: This will completely remove:"
log_warn "  - User: $PROJECT_SLUG"
log_warn "  - Home directory: /home/$PROJECT_SLUG"
log_warn "  - All data and containers"
log_warn "  - Podman images (stored in home directory)"
log_warn "=========================================="
echo ""
read -p "Are you sure you want to continue? (type 'yes' to confirm): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    log_info "Destroy cancelled."
    exit 0
fi

# Step 1: Stop and disable the systemd service
log_info "Stopping systemd service..."
if systemctl_user "$PROJECT_SLUG" is-active "$PROJECT_SLUG-container.service" &>/dev/null; then
    stop_service "$PROJECT_SLUG"
    log_info "Waiting for systemd to fully shut down..."
    sleep 2
else
    log_info "Service is not running, skipping stop."
fi

log_info "Disabling systemd service..."
if systemctl_user "$PROJECT_SLUG" is-enabled "$PROJECT_SLUG-container.service" &>/dev/null; then
    systemctl_user "$PROJECT_SLUG" disable "$PROJECT_SLUG-container.service"
else
    log_info "Service is not enabled, skipping disable."
fi

# Step 2: Stop any running containers (cleanup, though they're in home dir)
log_info "Stopping and removing any containers..."
if podman_user "$PROJECT_SLUG" ps -q --filter "name=$PROJECT_SLUG-container" 2>/dev/null | grep -q .; then
    podman_user "$PROJECT_SLUG" stop "$PROJECT_SLUG-container" 2>/dev/null || true
fi
podman_user "$PROJECT_SLUG" rm -f "$PROJECT_SLUG-container" 2>/dev/null || true

# Step 3: Disable linger
log_info "Disabling linger for $PROJECT_SLUG..."
loginctl disable-linger "$PROJECT_SLUG"

# Step 4: Kill all remaining processes owned by the user
log_info "Killing all processes owned by $PROJECT_SLUG..."
if pgrep -u "$PROJECT_SLUG" >/dev/null 2>&1; then
    pkill -u "$PROJECT_SLUG" || true
    log_info "Waiting for processes to terminate..."
    sleep 2
    # Force kill if anything remains
    if pgrep -u "$PROJECT_SLUG" >/dev/null 2>&1; then
        log_warn "Some processes still running, force killing..."
        pkill -9 -u "$PROJECT_SLUG" || true
        sleep 1
    fi
else
    log_info "No processes found for $PROJECT_SLUG"
fi

# Step 5: Delete the user and home directory
log_info "Deleting user $PROJECT_SLUG and home directory..."
userdel -r "$PROJECT_SLUG"

log_info "=========================================="
log_info "Project $PROJECT_SLUG has been completely removed!"
log_info "=========================================="
log_info ""
log_info "Don't forget to:"
log_info "  - Remove the entry from your Caddyfile"
log_info "  - Reload Caddy: sudo systemctl reload caddy"
log_info "  - Remove the deploy key from your git repository"
