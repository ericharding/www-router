#!/bin/bash
set -euo pipefail

# Script to rollback a project to the previous image
# Usage: ./rollback.sh <project_slug>
# Example: ./rollback.sh proj1

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

# Check if :old image exists
if ! check_image_exists "$PROJECT_SLUG" "old"; then
    log_error "No backup image found ($PROJECT_SLUG-image:old)"
    log_error "Cannot rollback - no previous version available"
    exit 1
fi

log_warn "=========================================="
log_warn "ROLLBACK WARNING"
log_warn "=========================================="
log_warn "This will:"
log_warn "  1. Stop the current container"
log_warn "  2. Tag current image as :broken"
log_warn "  3. Restore the previous image"
log_warn "  4. Restart the container"
echo ""
read -p "Are you sure you want to rollback $PROJECT_SLUG? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    log_info "Rollback cancelled"
    exit 0
fi

log_info "Rolling back $PROJECT_SLUG..."

# Stop the service
stop_service "$PROJECT_SLUG"

# Tag current image as :broken (remove old :broken if exists)
log_info "Tagging current image as :broken..."
if check_image_exists "$PROJECT_SLUG" "broken"; then
    podman_user "$PROJECT_SLUG" rmi "$PROJECT_SLUG-image:broken"
fi

if check_image_exists "$PROJECT_SLUG"; then
    podman_user "$PROJECT_SLUG" tag "$PROJECT_SLUG-image" "$PROJECT_SLUG-image:broken"
fi

# Remove current image tag
log_info "Removing current image tag..."
podman_user "$PROJECT_SLUG" rmi "$PROJECT_SLUG-image" 2>/dev/null || true

# Restore :old image as main image
log_info "Restoring previous image..."
podman_user "$PROJECT_SLUG" tag "$PROJECT_SLUG-image:old" "$PROJECT_SLUG-image"

# Restart service
start_service "$PROJECT_SLUG"

# Check status
show_service_status "$PROJECT_SLUG"

echo ""
log_info "=========================================="
log_info "Rollback complete for $PROJECT_SLUG!"
log_info "=========================================="
log_info "The previous version is now running"
log_info ""
log_info "Available images:"
podman_user "$PROJECT_SLUG" images | grep "$PROJECT_SLUG-image" || true
echo ""
log_info "If you need to restore the 'broken' version:"
echo "  sudo -u $PROJECT_SLUG podman tag $PROJECT_SLUG-image:broken $PROJECT_SLUG-image"
echo "  sudo ./scripts/restart.sh $PROJECT_SLUG"
