#!/bin/bash
set -euo pipefail

# Script to update a project (git pull, rebuild, restart)
# Usage: ./update.sh <project_slug>
# Example: ./update.sh proj1

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

# Check if app directory exists
check_app_directory "$PROJECT_SLUG"

log_info "Updating $PROJECT_SLUG..."

# Get current commit hash before pull
BEFORE_COMMIT=$(git_user "$PROJECT_SLUG" rev-parse HEAD)

# Pull latest changes
log_info "Pulling latest changes from git..."
git_user "$PROJECT_SLUG" pull

# Get commit hash after pull
AFTER_COMMIT=$(git_user "$PROJECT_SLUG" rev-parse HEAD)

# Check if there were any changes
if [ "$BEFORE_COMMIT" = "$AFTER_COMMIT" ]; then
    log_info "No changes detected. Already up to date."
    exit 0
fi

log_info "Changes detected. Rebuilding container image..."
log_info "  Before: $BEFORE_COMMIT"
log_info "  After:  $AFTER_COMMIT"

# Tag current image as :old (remove old backup first if it exists)
log_info "Backing up current image as $PROJECT_SLUG-image:old..."
if check_image_exists "$PROJECT_SLUG" "old"; then
    podman_user "$PROJECT_SLUG" rmi "$PROJECT_SLUG-image:old"
fi

# Only tag if the current image exists
if check_image_exists "$PROJECT_SLUG"; then
    podman_user "$PROJECT_SLUG" tag "$PROJECT_SLUG-image" "$PROJECT_SLUG-image:old"
else
    log_warn "Current image does not exist, skipping backup"
fi

# Build new image
log_info "Building new image..."
podman_user "$PROJECT_SLUG" build -t "$PROJECT_SLUG-image" "/home/$PROJECT_SLUG/app/"

# Restart service
restart_service "$PROJECT_SLUG"

# Check status
show_service_status "$PROJECT_SLUG"

echo ""
log_info "=========================================="
log_info "Update complete for $PROJECT_SLUG!"
log_info "=========================================="
log_info "New commit: $AFTER_COMMIT"
log_info ""
log_info "To rollback to previous version, run:"
echo "  sudo ./scripts/rollback.sh $PROJECT_SLUG"
