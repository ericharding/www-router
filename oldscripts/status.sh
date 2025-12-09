#!/bin/bash
set -euo pipefail

# Script to check status of projects
# Usage: ./status.sh <project_slug> [-p] [-s] OR ./status.sh -a
# Options:
#   -p  Show podman ps output for the project
#   -s  Show systemctl status for the project
#   -a  Show status for all projects
# Example: ./status.sh proj1 -p
# Example: ./status.sh proj1 -s
# Example: ./status.sh proj1 -p -s
# Example: ./status.sh proj1 (shows both by default)
# Example: ./status.sh -a (show status for all projects)

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Check if script is run with sudo
require_sudo

# Parse arguments
if [ $# -lt 1 ]; then
    log_error "Usage: $0 <project_slug> [-p] [-s] OR $0 -a"
    log_error "Options:"
    log_error "  -p  Show podman ps output"
    log_error "  -s  Show systemctl status"
    log_error "  -a  Show status for all projects"
    log_error "Example: $0 proj1 -p"
    log_error "Example: $0 proj1 -s"
    log_error "Example: $0 proj1 -p -s"
    log_error "Example: $0 -a"
    exit 1
fi

# Set default option to show both if no option specified
SHOW_PODMAN=false
SHOW_SYSTEMCTL=false
SHOW_ALL_USERS=false

# Parse options
while getopts ":psa" opt; do
    case $opt in
        p)
            SHOW_PODMAN=true
            ;;
        s)
            SHOW_SYSTEMCTL=true
            ;;
        a)
            SHOW_ALL_USERS=true
            ;;
        \?)
            log_error "Invalid option: -$OPTARG"
            exit 1
            ;;
    esac
done

# Shift processed options
shift $((OPTIND-1))

# Handle -a option (show all projects)
if [ "$SHOW_ALL_USERS" = true ]; then
    # No project slug needed for -a option
    :
else
    # Need project slug for non -a mode
    if [ $# -lt 1 ]; then
        log_error "Usage: $0 <project_slug> [-p] [-s] OR $0 -a"
        log_error "Options:"
        log_error "  -p  Show podman ps output"
        log_error "  -s  Show systemctl status"
        log_error "  -a  Show status for all projects"
        log_error "Example: $0 proj1 -p"
        log_error "Example: $0 proj1 -s"
        log_error "Example: $0 proj1 -p -s"
        log_error "Example: $0 -a"
        exit 1
    fi

    PROJECT_SLUG="$1"

    # Check if user exists
    check_user_exists "$PROJECT_SLUG"
fi

# If no options specified, default to show both
if [ "$SHOW_PODMAN" = false ] && [ "$SHOW_SYSTEMCTL" = false ]; then
    SHOW_PODMAN=true
    SHOW_SYSTEMCTL=true
fi

if [ "$SHOW_ALL_USERS" = true ]; then
    # Find all project users (users with home directories containing 'app')
    log_info "Checking status for all projects..."

    # Get all users that have app directories
    PROJECT_USERS=$(find /home -maxdepth 2 -name "app" -type d | sed 's|/home/||' | sed 's|/app||' | sort)

    if [ -z "$PROJECT_USERS" ]; then
        log_warn "No projects found"
        exit 0
    fi

    for PROJECT_SLUG in $PROJECT_USERS; do
        echo ""
        log_info "=== Status for $PROJECT_SLUG ==="
        echo ""

        # Show podman ps output
        if [ "$SHOW_PODMAN" = true ]; then
            log_info "Podman containers for $PROJECT_SLUG:"
            echo "----------------------------------------"
            podman_user "$PROJECT_SLUG" ps --filter "name=$PROJECT_SLUG" --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}"
            echo ""
        fi

        # Show systemctl status
        if [ "$SHOW_SYSTEMCTL" = true ]; then
            log_info "Systemctl service status for $PROJECT_SLUG:"
            echo "----------------------------------------"
            show_service_status "$PROJECT_SLUG"
            echo ""
        fi
    done

    log_info "Status check complete for all projects!"
else
    log_info "Checking status for $PROJECT_SLUG..."

    # Show podman ps output if requested
    if [ "$SHOW_PODMAN" = true ]; then
        echo ""
        log_info "Podman containers for $PROJECT_SLUG:"
        echo "----------------------------------------"
        podman_user "$PROJECT_SLUG" ps --filter "name=$PROJECT_SLUG" --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}"
        echo ""
    fi

    # Show systemctl status if requested
    if [ "$SHOW_SYSTEMCTL" = true ]; then
        echo ""
        log_info "Systemctl service status for $PROJECT_SLUG:"
        echo "----------------------------------------"
        show_service_status "$PROJECT_SLUG"
        echo ""
    fi

    log_info "Status check complete for $PROJECT_SLUG!"
fi
