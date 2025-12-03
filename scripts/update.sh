#!/bin/bash
set -euo pipefail

# Script to update a project (git pull, rebuild, restart)
# Usage: ./update.sh <project_slug>
# Example: ./update.sh proj1

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

# Check if app directory exists
if [ ! -d "/home/$PROJECT_SLUG/app" ]; then
    log_error "App directory /home/$PROJECT_SLUG/app does not exist"
    exit 1
fi

# Get user ID
USER_ID=$(id -u "$PROJECT_SLUG")

log_info "Updating $PROJECT_SLUG..."

# Get current commit hash before pull
BEFORE_COMMIT=$(sudo -u "$PROJECT_SLUG" git -C "/home/$PROJECT_SLUG/app" rev-parse HEAD)

# Pull latest changes
log_info "Pulling latest changes from git..."
sudo -u "$PROJECT_SLUG" git -C "/home/$PROJECT_SLUG/app" pull

# Get commit hash after pull
AFTER_COMMIT=$(sudo -u "$PROJECT_SLUG" git -C "/home/$PROJECT_SLUG/app" rev-parse HEAD)

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
if sudo -u "$PROJECT_SLUG" podman image exists "$PROJECT_SLUG-image:old" 2>/dev/null; then
    sudo -u "$PROJECT_SLUG" podman rmi "$PROJECT_SLUG-image:old"
fi

# Only tag if the current image exists
if sudo -u "$PROJECT_SLUG" podman image exists "$PROJECT_SLUG-image" 2>/dev/null; then
    sudo -u "$PROJECT_SLUG" podman tag "$PROJECT_SLUG-image" "$PROJECT_SLUG-image:old"
else
    log_warn "Current image does not exist, skipping backup"
fi

# Build new image
log_info "Building new image..."
sudo -u "$PROJECT_SLUG" podman build -t "$PROJECT_SLUG-image" "/home/$PROJECT_SLUG/app/"

# Restart service
log_info "Restarting service..."
sudo -u "$PROJECT_SLUG" XDG_RUNTIME_DIR="/run/user/$USER_ID" \
    systemctl --user restart "$PROJECT_SLUG-container.service"

# Check status
log_info "Checking service status..."
sleep 2
sudo -u "$PROJECT_SLUG" XDG_RUNTIME_DIR="/run/user/$USER_ID" \
    systemctl --user status "$PROJECT_SLUG-container.service" --no-pager || true

echo ""
log_info "=========================================="
log_info "Update complete for $PROJECT_SLUG!"
log_info "=========================================="
log_info "New commit: $AFTER_COMMIT"
log_info ""
log_info "To rollback to previous version, run:"
echo "  sudo ./scripts/rollback.sh $PROJECT_SLUG"
