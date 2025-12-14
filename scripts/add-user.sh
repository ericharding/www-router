#!/bin/bash

set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root"
    echo "Please run with: sudo $0"
    exit 1
fi

# Default values
ENABLE_LINGER=false
CREATE_ENV=false
ENV_SOURCE_FILE=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --linger)
            ENABLE_LINGER=true
            shift
            ;;
        --env)
            CREATE_ENV=true
            if [[ -n "$2" && "$2" != -* ]]; then
                ENV_SOURCE_FILE="$2"
                shift
            fi
            shift
            ;;
        *)
            if [[ -z "$NEW_USERNAME" ]]; then
                NEW_USERNAME="$1"
                shift
            else
                echo "Error: Unexpected argument $1"
                echo "Usage: $0 [--linger] [--env [source_file]] <username>"
                exit 1
            fi
            ;;
    esac
done

# Check if username is provided
if [ -z "$NEW_USERNAME" ]; then
    echo "Error: No username provided"
    echo "Usage: $0 [--linger] [--env [source_file]] <username>"
    exit 1
fi

# Check if user already exists
if id "$NEW_USERNAME" &>/dev/null; then
    echo "User $NEW_USERNAME already exists"
    exit 0
fi

# Create the user
echo "Creating user $NEW_USERNAME..."
sudo useradd -m -s /bin/bash "$NEW_USERNAME"

# Enable linger if requested
if [ "$ENABLE_LINGER" = true ]; then
    echo "Enabling linger for $NEW_USERNAME..."
    sudo loginctl enable-linger "$NEW_USERNAME"
fi

# Create .env file if requested
if [ "$CREATE_ENV" = true ]; then
    USER_HOME=$(eval echo "~$NEW_USERNAME")
    ENV_FILE="$USER_HOME/.env"

    echo "Creating .env file at $ENV_FILE..."

    if [[ -n "$ENV_SOURCE_FILE" && -f "$ENV_SOURCE_FILE" ]]; then
        # Copy from source file
        sudo -u "$NEW_USERNAME" cp "$ENV_SOURCE_FILE" "$ENV_FILE"
    else
        # Create empty .env file with comments
        sudo -u "$NEW_USERNAME" cat << EOF > "$ENV_FILE"
# Environment variables for $NEW_USERNAME
# Add your custom environment variables below

# Example variables:
# DATABASE_URL=postgres://user:password@localhost:5432/dbname
# API_KEY=your_api_key_here
# DEBUG=true
EOF
    fi

    sudo -u "$NEW_USERNAME" chmod 600 "$ENV_FILE"
fi

echo "User $NEW_USERNAME created successfully"
if [ "$ENABLE_LINGER" = true ]; then
    echo "Linger enabled for $NEW_USERNAME"
fi
if [ "$CREATE_ENV" = true ]; then
    echo ".env file created for $NEW_USERNAME"
fi
