#!/bin/bash
set -euo pipefail

# Script to set up a new project with user, container, and systemd service
# Usage: ./new.sh <project_slug> <git_uri> [branch]
# Example: ./new.sh proj1 git@github.com:user/repo.git prod

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Check if script is run with sudo
require_sudo

# Parse arguments
if [ $# -lt 2 ] || [ $# -gt 3 ]; then
    log_error "Usage: $0 <project_slug> <git_uri> [env_file]"
    log_error "Example: $0 proj1 git@github.com:user/repo.git /path/to/custom.env"
    log_error "If env_file not provided, will use repo's .env.example or create empty .env"
    exit 1
fi

PROJECT_SLUG="$1"
GIT_URI="$2"
ENV_FILE="$3"

# Extract git host from URI
GIT_HOST=$(echo "$GIT_URI" | sed -n 's/.*@\([^:]*\):.*/\1/p')
if [ -z "$GIT_HOST" ]; then
    log_error "Could not extract git host from URI: $GIT_URI"
    exit 1
fi

log_info "Setting up project: $PROJECT_SLUG"
log_info "  Git URI: $GIT_URI"
log_info "  Git Host: $GIT_HOST"

# Check if user already exists
check_user_not_exists "$PROJECT_SLUG"

# Step 1: Create project user
log_info "Creating user $PROJECT_SLUG..."
useradd -m -s /sbin/nologin "$PROJECT_SLUG"
loginctl enable-linger "$PROJECT_SLUG"

# Get the user ID and calculate port
USER_ID=$(id -u "$PROJECT_SLUG")
PORT=$((8000 + USER_ID))

log_info "  User ID: $USER_ID"
log_info "  Port: $PORT"

# Step 2: Create directories and .env file
log_info "Creating directories..."
mkdir -p "/home/$PROJECT_SLUG/container-data"
mkdir -p "/home/$PROJECT_SLUG/.ssh"
chown -R "$PROJECT_SLUG:$PROJECT_SLUG" "/home/$PROJECT_SLUG"
chmod 700 "/home/$PROJECT_SLUG/.ssh"

# .env file will be created after cloning repository

# Make systemd work for user
echo export XDG_RUNTIME_DIR=/run/user/$USER_ID >> /home/$PROJECT_SLUG/.bashrc

# Step 3: Generate SSH key
log_info "Generating SSH key..."
sudo -u "$PROJECT_SLUG" ssh-keygen -t ed25519 -f "/home/$PROJECT_SLUG/.ssh/id_ed25519" -N "" -C "$PROJECT_SLUG-deploy-key"

# Step 4: Display public key and wait for user
echo ""
echo "=========================================="
echo "DEPLOY KEY - Add this to your git repository:"
echo "=========================================="
cat "/home/$PROJECT_SLUG/.ssh/id_ed25519.pub"
echo "=========================================="
echo ""
log_warn "Add the above public key as a deploy key to your repository"
log_warn "GitHub: Settings � Deploy keys � Add deploy key"
log_warn "GitLab: Settings � Repository � Deploy keys � Add key"
echo ""
read -p "Press ENTER once you have added the deploy key..."

# Step 5: Add git host to known_hosts
log_info "Adding $GIT_HOST to known_hosts..."
sudo -u "$PROJECT_SLUG" ssh-keyscan "$GIT_HOST" >> "/home/$PROJECT_SLUG/.ssh/known_hosts" 2>/dev/null

# Step 6: Clone repository
log_info "Cloning repository..."
sudo -u "$PROJECT_SLUG" git clone "$GIT_URI" "/home/$PROJECT_SLUG/app"

# Verify Dockerfile exists
check_dockerfile "$PROJECT_SLUG"

# Step 6.5: Create .env file
log_info "Creating .env file..."
if [ -n "$ENV_FILE" ]; then
    # Use provided environment file
    log_info "Using provided environment file: $ENV_FILE"
    if [ ! -f "$ENV_FILE" ]; then
        log_error "Environment file not found: $ENV_FILE"
        exit 1
    fi
    cp "$ENV_FILE" "/home/$PROJECT_SLUG/.env"
elif [ -f "/home/$PROJECT_SLUG/app/.env.example" ]; then
    # Use repo's .env.example
    log_info "Using repository's .env.example"
    cp "/home/$PROJECT_SLUG/app/.env.example" "/home/$PROJECT_SLUG/.env"
else
    # Create empty .env with default container settings
    log_info "Creating default .env file"
    cat > "/home/$PROJECT_SLUG/.env" << 'ENV_EOF'
# Container configuration
CONTAINER_PORT=80
CONTAINER_READONLY=true
CONTAINER_CAPS=NET_BIND_SERVICE,CHOWN
CONTAINER_VOLUMES=container-data:/data:Z
CONTAINER_TMPFS=/tmp

# Add your application environment variables below
ENV_EOF
fi

# Set ownership and permissions
chown "$PROJECT_SLUG:$PROJECT_SLUG" "/home/$PROJECT_SLUG/.env"
chmod 600 "/home/$PROJECT_SLUG/.env"

# Step 7: Build container image
log_info "Building container image..."
podman_user "$PROJECT_SLUG" build -t "$PROJECT_SLUG-image" "/home/$PROJECT_SLUG/app/"

# Step 8: Create systemd service
log_info "Creating systemd service..."
mkdir -p "/home/$PROJECT_SLUG/.config/systemd/user"
chown -R "$PROJECT_SLUG:$PROJECT_SLUG" "/home/$PROJECT_SLUG/.config"

cat > "/home/$PROJECT_SLUG/.config/systemd/user/$PROJECT_SLUG-container.service" <<EOF
[Unit]
Description=$PROJECT_SLUG Container
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
NotifyAccess=all
Restart=always
RestartSec=10s
TimeoutStartSec=120s

# Load environment file for container configuration
EnvironmentFile=/home/$PROJECT_SLUG/.env

# Resource limits
MemoryMax=1G
CPUQuota=100%

# Security settings
NoNewPrivileges=true
PrivateTmp=true

# Run the container
ExecStartPre=-/usr/bin/podman kill $PROJECT_SLUG-container
ExecStartPre=-/usr/bin/podman rm $PROJECT_SLUG-container
ExecStart=/bin/bash -c 'exec /usr/bin/podman run \\
  --name $PROJECT_SLUG-container \\
  --publish 127.0.0.1:$PORT:\${CONTAINER_PORT:-80} \\
  --env-file /home/$PROJECT_SLUG/.env \\
  --volume /home/$PROJECT_SLUG/\${CONTAINER_VOLUMES:-container-data:/data:Z} \\
  --security-opt no-new-privileges=true \\
  --cap-drop ALL \\
  \${CONTAINER_CAPS:+\$(echo "\$CONTAINER_CAPS" | sed "s/,/ --cap-add /g" | sed "s/^/--cap-add /")} \\
  \${CONTAINER_READONLY:+\$([ "\$CONTAINER_READONLY" = "true" ] && echo "--read-only")} \\
  \${CONTAINER_TMPFS:+\$(echo "\$CONTAINER_TMPFS" | sed "s/,/ --tmpfs /g" | sed "s/^/--tmpfs /")} \\
  $PROJECT_SLUG-image'

ExecStop=/usr/bin/podman stop -t 10 $PROJECT_SLUG-container
ExecStopPost=/usr/bin/podman rm -f $PROJECT_SLUG-container

[Install]
WantedBy=default.target
EOF

chown "$PROJECT_SLUG:$PROJECT_SLUG" "/home/$PROJECT_SLUG/.config/systemd/user/$PROJECT_SLUG-container.service"

# Step 9: Enable and start service
log_info "Enabling and starting service..."
systemctl_user "$PROJECT_SLUG" daemon-reload
systemctl_user "$PROJECT_SLUG" enable --now "$PROJECT_SLUG-container.service"

# Step 10: Check status
show_service_status "$PROJECT_SLUG"

echo ""
log_info "=========================================="
log_info "Setup complete for $PROJECT_SLUG!"
log_info "=========================================="
log_info "Port: $PORT"
log_info ""
log_info "Add this to your Caddyfile:"
echo ""
echo "$PROJECT_SLUG.yourdomain.com {"
echo "    reverse_proxy 127.0.0.1:$PORT"
echo "    "
echo "    header {"
echo "        Strict-Transport-Security \"max-age=31536000; includeSubDomains; preload\""
echo "        X-Frame-Options \"SAMEORIGIN\""
echo "        X-Content-Type-Options \"nosniff\""
echo "        X-XSS-Protection \"1; mode=block\""
echo "        Referrer-Policy \"strict-origin-when-cross-origin\""
echo "    }"
echo "    "
echo "    log {"
echo "        output file /var/log/caddy/$PROJECT_SLUG.log"
echo "        format json"
echo "    }"
echo "}"
echo ""
log_info "Then reload Caddy: sudo systemctl reload caddy"
log_info ""
log_info "View logs with: sudo -u $PROJECT_SLUG XDG_RUNTIME_DIR=/run/user/$USER_ID journalctl --user -u $PROJECT_SLUG-container.service -f"
