#!/bin/bash
set -euo pipefail

# Script to restart a project container
# Usage: ./restart.sh <project_slug>
# Example: ./restart.sh proj1

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

log_info "Restarting $PROJECT_SLUG container..."
restart_service "$PROJECT_SLUG"

# Check status
show_service_status "$PROJECT_SLUG"

log_info "Restart complete!"
