#!/bin/bash

# Shared library of functions used by all management scripts. This file is automatically sourced by other scripts and provides:

# **Logging Functions:**
# - `log_info()` - Green info messages
# - `log_warn()` - Yellow warning messages
# - `log_error()` - Red error messages

# **State Checking Functions:**
# - `require_sudo()` - Verify script is run with sudo
# - `check_user_exists()` - Verify project user exists
# - `check_user_not_exists()` - Verify project user doesn't exist
# - `check_app_directory()` - Verify app directory exists
# - `check_dockerfile()` - Verify Dockerfile exists
# - `check_image_exists()` - Check if podman image exists

# **Helper Functions:**
# - `get_user_id()` - Get user ID for a project
# - `get_port()` - Calculate port from user ID
# - `systemctl_user()` - Execute systemctl as project user
# - `podman_user()` - Execute podman as project user
# - `git_user()` - Execute git as project user
# - `show_service_status()` - Display service status
# - `restart_service()` - Restart systemd service
# - `stop_service()` - Stop systemd service
# - `start_service()` - Start systemd service


# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
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
function require_sudo() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Please run this script with sudo"
        exit 1
    fi
}

# Check if user exists
function check_user_exists() {
    local project_slug="$1"
    if ! id "$project_slug" &>/dev/null; then
        log_error "User $project_slug does not exist"
        exit 1
    fi
}

# Check if user does not exist (for new project creation)
function check_user_not_exists() {
    local project_slug="$1"
    if id "$project_slug" &>/dev/null; then
        log_error "User $project_slug already exists"
        exit 1
    fi
}

# Check if app directory exists
function check_app_directory() {
    local project_slug="$1"
    if [ ! -d "/home/$project_slug/app" ]; then
        log_error "App directory /home/$project_slug/app does not exist"
        exit 1
    fi
}

# Check if Dockerfile exists
function check_dockerfile() {
    local project_slug="$1"
    if [ ! -f "/home/$project_slug/app/Dockerfile" ]; then
        log_error "Dockerfile not found in repository root"
        exit 1
    fi
}

# Check if podman image exists
function check_image_exists() {
    local project_slug="$1"
    local image_tag="${2:-}" # Optional tag, defaults to empty (main image)
    local image_name="$project_slug-image"
    
    if [ -n "$image_tag" ]; then
        image_name="$image_name:$image_tag"
    fi
    
    if ! sudo -u "$project_slug" podman image exists "$image_name" 2>/dev/null; then
        return 1
    fi
    return 0
}

# Get user ID for a project
function get_user_id() {
    local project_slug="$1"
    id -u "$project_slug"
}

# Get port for a project (calculated from user ID)
function get_port() {
    local project_slug="$1"
    local user_id=$(get_user_id "$project_slug")
    echo $((8000 + user_id))
}

# Execute systemctl command as project user
function systemctl_user() {
    local project_slug="$1"
    shift # Remove first argument, rest are systemctl args
    local user_id=$(get_user_id "$project_slug")

    sudo -H -u "$project_slug" XDG_RUNTIME_DIR="/run/user/$user_id" \
        systemctl --user "$@"
}

# Execute podman command as project user
function podman_user() {
    local project_slug="$1"
    shift # Remove first argument, rest are podman args

    sudo -H -u "$project_slug" sh -c "cd /home/$project_slug && podman $*"
}

# Execute git command as project user in app directory
function git_user() {
    local project_slug="$1"
    shift # Remove first argument, rest are git args

    sudo -H -u "$project_slug" git -C "/home/$project_slug/app" "$@"
}

# Show service status
function show_service_status() {
    local project_slug="$1"
    local user_id=$(get_user_id "$project_slug")

    log_info "Checking service status..."
    sleep 1
    sudo -H -u "$project_slug" XDG_RUNTIME_DIR="/run/user/$user_id" \
        systemctl --user status "$project_slug-container.service" --no-pager || true
}

# Restart service
function restart_service() {
    local project_slug="$1"
    local user_id=$(get_user_id "$project_slug")

    log_info "Restarting service..."
    sudo -H -u "$project_slug" XDG_RUNTIME_DIR="/run/user/$user_id" \
        systemctl --user restart "$project_slug-container.service"
}

# Stop service
function stop_service() {
    local project_slug="$1"
    local user_id=$(get_user_id "$project_slug")

    log_info "Stopping service..."
    sudo -H -u "$project_slug" XDG_RUNTIME_DIR="/run/user/$user_id" \
        systemctl --user stop "$project_slug-container.service"
}

# Start service
function start_service() {
    local project_slug="$1"
    local user_id=$(get_user_id "$project_slug")
    
    log_info "Starting service..."
    sudo -u "$project_slug" XDG_RUNTIME_DIR="/run/user/$user_id" \
        systemctl --user start "$project_slug-container.service"
}
