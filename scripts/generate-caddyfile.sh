#!/bin/bash
set -euo pipefail

# Script to generate Caddyfile from projects.json
# Usage: ./generate-caddyfile.sh [domain] [email]
# Example: ./generate-caddyfile.sh yourdomain.com admin@yourdomain.com

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

function log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" >&2
}

function log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Default values
DOMAIN="${1:-yourdomain.com}"
EMAIL="${2:-your-email@example.com}"
CONFIG_FILE="/etc/router-projects.json"

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    log_error "jq is required but not installed. Install it with: sudo apt install jq"
    exit 1
fi

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    log_error "Config file not found: $CONFIG_FILE"
    log_error "Create it with: sudo touch $CONFIG_FILE && echo '[]' | sudo tee $CONFIG_FILE"
    exit 1
fi

log_info "Generating Caddyfile from $CONFIG_FILE"
log_info "Domain: $DOMAIN"
log_info "Email: $EMAIL"

# Start Caddyfile
cat <<EOF
# Global options
{
    email $EMAIL
    # Uncomment for staging (testing):
    # acme_ca https://acme-staging-v02.api.letsencrypt.org/directory
}

EOF

# Read projects from JSON and generate Caddyfile entries
jq -c '.[]' "$CONFIG_FILE" | while read -r project; do
    slug=$(echo "$project" | jq -r '.slug')

    # Skip if slug is empty or null
    if [ -z "$slug" ] || [ "$slug" = "null" ]; then
        continue
    fi

    # Check if user exists
    if ! id "$slug" &>/dev/null; then
        log_error "User $slug does not exist - skipping" >&2
        continue
    fi

    # Calculate port from user ID
    user_id=$(id -u "$slug")
    port=$((8000 + user_id))

    # Generate Caddyfile block
    cat <<EOF
# $slug
$slug.$DOMAIN {
    reverse_proxy 127.0.0.1:$port

    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        X-Frame-Options "SAMEORIGIN"
        X-Content-Type-Options "nosniff"
        X-XSS-Protection "1; mode=block"
        Referrer-Policy "strict-origin-when-cross-origin"
    }

    log {
        output file /var/log/caddy/$slug.log
        format json
    }
}

EOF
done

log_info "Caddyfile generation complete!"
