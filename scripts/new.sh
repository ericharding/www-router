#!/bin/bash
set -euo pipefail

# Script to set up a new project with user, container, and systemd service
# Usage: ./new.sh <project_slug> <git_uri> <branch>
# Example: ./new.sh proj1 git@github.com:user/repo.git prod

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
if [ $# -ne 3 ]; then
    log_error "Usage: $0 <project_slug> <git_uri> <branch>"
    log_error "Example: $0 proj1 git@github.com:user/repo.git prod"
    exit 1
fi

PROJECT_SLUG="$1"
GIT_URI="$2"
BRANCH="$3"

# Extract git host from URI
GIT_HOST=$(echo "$GIT_URI" | sed -n 's/.*@\([^:]*\):.*/\1/p')
if [ -z "$GIT_HOST" ]; then
    log_error "Could not extract git host from URI: $GIT_URI"
    exit 1
fi

log_info "Setting up project: $PROJECT_SLUG"
log_info "  Git URI: $GIT_URI"
log_info "  Branch: $BRANCH"
log_info "  Git Host: $GIT_HOST"

# Check if user already exists
if id "$PROJECT_SLUG" &>/dev/null; then
    log_error "User $PROJECT_SLUG already exists"
    exit 1
fi

# Step 1: Create project user
log_info "Creating user $PROJECT_SLUG..."
useradd -m -s /sbin/nologin "$PROJECT_SLUG"
loginctl enable-linger "$PROJECT_SLUG"

# Get the user ID and calculate port/IP
USER_ID=$(id -u "$PROJECT_SLUG")
PORT=$((8000 + USER_ID))
# Map UID to IP range 10.67.0.10-255 (246 available IPs)
IP="10.67.0.$((10 + (USER_ID % 246)))"

log_info "  User ID: $USER_ID"
log_info "  Port: $PORT"
log_info "  IP: $IP"

# Step 2: Create directories and .env file
log_info "Creating directories..."
mkdir -p "/home/$PROJECT_SLUG/container-data"
mkdir -p "/home/$PROJECT_SLUG/.ssh"
chown -R "$PROJECT_SLUG:$PROJECT_SLUG" "/home/$PROJECT_SLUG"
chmod 700 "/home/$PROJECT_SLUG/.ssh"

# Create empty .env file for project-specific environment variables
log_info "Creating .env file..."
touch "/home/$PROJECT_SLUG/.env"
chown "$PROJECT_SLUG:$PROJECT_SLUG" "/home/$PROJECT_SLUG/.env"
chmod 600 "/home/$PROJECT_SLUG/.env"

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
sudo -u "$PROJECT_SLUG" git clone --branch "$BRANCH" "$GIT_URI" "/home/$PROJECT_SLUG/app"

# Verify Dockerfile exists
if [ ! -f "/home/$PROJECT_SLUG/app/Dockerfile" ]; then
    log_error "Dockerfile not found in repository root"
    exit 1
fi

# Step 7: Build container image
log_info "Building container image..."
sudo -u "$PROJECT_SLUG" podman build -t "$PROJECT_SLUG-image" "/home/$PROJECT_SLUG/app/"

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

# Resource limits
MemoryMax=1G
CPUQuota=100%

# Security settings
NoNewPrivileges=true
PrivateTmp=true

# Run the container
ExecStartPre=-/usr/bin/podman kill $PROJECT_SLUG-container
ExecStartPre=-/usr/bin/podman rm $PROJECT_SLUG-container
ExecStart=/usr/bin/podman run \\
  --name $PROJECT_SLUG-container \\
  --network router-net \\
  --ip $IP \\
  --publish 127.0.0.1:$PORT:80 \\
  --env-file /home/$PROJECT_SLUG/.env \\
  --volume /home/$PROJECT_SLUG/container-data:/data:Z \\
  --security-opt no-new-privileges=true \\
  --cap-drop ALL \\
  --cap-add NET_BIND_SERVICE \\
  --read-only \\
  --tmpfs /tmp \\
  --label io.containers.autoupdate=registry \\
  $PROJECT_SLUG-image

ExecStop=/usr/bin/podman stop -t 10 $PROJECT_SLUG-container
ExecStopPost=/usr/bin/podman rm -f $PROJECT_SLUG-container

[Install]
WantedBy=default.target
EOF

chown "$PROJECT_SLUG:$PROJECT_SLUG" "/home/$PROJECT_SLUG/.config/systemd/user/$PROJECT_SLUG-container.service"

# Step 9: Enable and start service
log_info "Enabling and starting service..."
sudo -u "$PROJECT_SLUG" XDG_RUNTIME_DIR="/run/user/$USER_ID" systemctl --user daemon-reload
sudo -u "$PROJECT_SLUG" XDG_RUNTIME_DIR="/run/user/$USER_ID" systemctl --user enable --now "$PROJECT_SLUG-container.service"

# Step 10: Check status
log_info "Checking service status..."
sleep 2
sudo -u "$PROJECT_SLUG" XDG_RUNTIME_DIR="/run/user/$USER_ID" systemctl --user status "$PROJECT_SLUG-container.service" --no-pager || true

echo ""
log_info "=========================================="
log_info "Setup complete for $PROJECT_SLUG!"
log_info "=========================================="
log_info "Port: $PORT"
log_info "IP: $IP"
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
