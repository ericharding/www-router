#!/bin/bash
set -euo pipefail

# Script to rollback a project to the previous image
# Usage: ./rollback.sh <project_slug>
# Example: ./rollback.sh proj1

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

function log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

function log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

function log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if script is run with sudo
if [ "$EUID" -ne 0 ]; then
    log_error "Please run this script with sudo"
    exit 1
fi

# Parse arguments
if [ $# -ne 1 ]; then
    log_error "Usage: $0 <project_slug>"
    log_error "Example: $0 proj1"
    exit 1
fi

PROJECT_SLUG="$1"

# Check if user exists
if ! id "$PROJECT_SLUG" &>/dev/null; then
    log_error "User $PROJECT_SLUG does not exist"
    exit 1
fi

# Check if :old image exists
if ! sudo -u "$PROJECT_SLUG" podman image exists "$PROJECT_SLUG-image:old" 2>/dev/null; then
    log_error "No backup image found ($PROJECT_SLUG-image:old)"
    log_error "Cannot rollback - no previous version available"
    exit 1
fi

# Get user ID
USER_ID=$(id -u "$PROJECT_SLUG")

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
log_info "Stopping service..."
sudo -u "$PROJECT_SLUG" XDG_RUNTIME_DIR="/run/user/$USER_ID" \
    systemctl --user stop "$PROJECT_SLUG-container.service"

# Tag current image as :broken (remove old :broken if exists)
log_info "Tagging current image as :broken..."
if sudo -u "$PROJECT_SLUG" podman image exists "$PROJECT_SLUG-image:broken" 2>/dev/null; then
    sudo -u "$PROJECT_SLUG" podman rmi "$PROJECT_SLUG-image:broken"
fi

if sudo -u "$PROJECT_SLUG" podman image exists "$PROJECT_SLUG-image" 2>/dev/null; then
    sudo -u "$PROJECT_SLUG" podman tag "$PROJECT_SLUG-image" "$PROJECT_SLUG-image:broken"
fi

# Remove current image tag
log_info "Removing current image tag..."
sudo -u "$PROJECT_SLUG" podman rmi "$PROJECT_SLUG-image" 2>/dev/null || true

# Restore :old image as main image
log_info "Restoring previous image..."
sudo -u "$PROJECT_SLUG" podman tag "$PROJECT_SLUG-image:old" "$PROJECT_SLUG-image"

# Restart service
log_info "Starting service..."
sudo -u "$PROJECT_SLUG" XDG_RUNTIME_DIR="/run/user/$USER_ID" \
    systemctl --user start "$PROJECT_SLUG-container.service"

# Check status
log_info "Checking service status..."
sleep 2
sudo -u "$PROJECT_SLUG" XDG_RUNTIME_DIR="/run/user/$USER_ID" \
    systemctl --user status "$PROJECT_SLUG-container.service" --no-pager || true

echo ""
log_info "=========================================="
log_info "Rollback complete for $PROJECT_SLUG!"
log_info "=========================================="
log_info "The previous version is now running"
log_info ""
log_info "Available images:"
sudo -u "$PROJECT_SLUG" podman images | grep "$PROJECT_SLUG-image" || true
echo ""
log_info "If you need to restore the 'broken' version:"
echo "  sudo -u $PROJECT_SLUG podman tag $PROJECT_SLUG-image:broken $PROJECT_SLUG-image"
echo "  sudo -u $PROJECT_SLUG XDG_RUNTIME_DIR=/run/user/$USER_ID systemctl --user restart $PROJECT_SLUG-container.service"
