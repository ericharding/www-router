#!/bin/bash
set -euo pipefail

# Script to restart a project container
# Usage: ./restart.sh <project_slug>
# Example: ./restart.sh proj1

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

function log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
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

# Get user ID
USER_ID=$(id -u "$PROJECT_SLUG")

log_info "Restarting $PROJECT_SLUG container..."
sudo -u "$PROJECT_SLUG" XDG_RUNTIME_DIR="/run/user/$USER_ID" \
    systemctl --user restart "$PROJECT_SLUG-container.service"

# Check status
log_info "Checking service status..."
sleep 1
sudo -u "$PROJECT_SLUG" XDG_RUNTIME_DIR="/run/user/$USER_ID" \
    systemctl --user status "$PROJECT_SLUG-container.service" --no-pager || true

log_info "Restart complete!"
