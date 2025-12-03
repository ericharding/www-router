#!/bin/bash
set -euo pipefail

# Script to bootstrap all projects from router-projects.json
# Usage: ./bootstrap.sh
# Example: sudo ./bootstrap.sh

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

CONFIG_FILE="/etc/router-projects.json"

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    log_error "jq is required but not installed. Install it with: sudo apt install jq"
    exit 1
fi

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    log_error "Config file not found: $CONFIG_FILE"
    exit 1
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log_info "=========================================="
log_info "Bootstrapping projects from $CONFIG_FILE"
log_info "=========================================="
echo ""

# Count projects
PROJECT_COUNT=$(jq 'length' "$CONFIG_FILE")
log_info "Found $PROJECT_COUNT projects in config"
echo ""

# Read projects from JSON
SUCCESS_COUNT=0
SKIP_COUNT=0
FAIL_COUNT=0

jq -c '.[]' "$CONFIG_FILE" | while read -r project; do
    slug=$(echo "$project" | jq -r '.slug')
    git_uri=$(echo "$project" | jq -r '.git')
    branch=$(echo "$project" | jq -r '.branch')

    # Skip if any field is empty or null
    if [ -z "$slug" ] || [ "$slug" = "null" ] || \
       [ -z "$git_uri" ] || [ "$git_uri" = "null" ] || \
       [ -z "$branch" ] || [ "$branch" = "null" ]; then
        log_warn "Skipping invalid project entry: $project"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        continue
    fi

    echo ""
    log_info "----------------------------------------"
    log_info "Processing: $slug"
    log_info "  Git: $git_uri"
    log_info "  Branch: $branch"
    log_info "----------------------------------------"

    # Check if user already exists
    if id "$slug" &>/dev/null; then
        log_warn "User $slug already exists - skipping"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        continue
    fi

    # Run new.sh for this project
    if "$SCRIPT_DIR/new.sh" "$slug" "$git_uri" "$branch"; then
        log_info "Successfully created $slug"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        log_error "Failed to create $slug"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

echo ""
log_info "=========================================="
log_info "Bootstrap complete!"
log_info "=========================================="
log_info "Success: $SUCCESS_COUNT"
log_info "Skipped: $SKIP_COUNT"
log_info "Failed: $FAIL_COUNT"
echo ""

if [ $SUCCESS_COUNT -gt 0 ]; then
    log_info "Next steps:"
    echo "  1. Generate Caddyfile: sudo ./scripts/generate-caddyfile.sh yourdomain.com admin@yourdomain.com > /etc/caddy/Caddyfile"
    echo "  2. Reload Caddy: sudo systemctl reload caddy"
fi
