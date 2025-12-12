#!/bin/bash

set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root"
    echo "Please run with: sudo $0"
    exit 1
fi

SLUG=$1
VERSION=$2

# Check if required arguments are provided
if [ -z "$SLUG" ]; then
    echo "Error: SLUG argument is required"
    echo "Usage: $0 <slug> <version>"
    exit 1
fi

if [ -z "$VERSION" ]; then
    echo "Error: VERSION argument is required"
    echo "Usage: $0 <slug> <version>"
    exit 1
fi

podman build -t $SLUG:$VERSION .

sudo podman image scp $USER@localhost::$SLUG:$VERSION
sudo podman tag $SLUG:$VERSION $SLUG:latest

