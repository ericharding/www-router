#!/bin/bash

set -e

# Check that we're not running as root
if [ "$EUID" -eq 0 ]; then
    echo "Error: This script should not be run as root"
    exit 1
fi

SLUG=$1
VERSION=$2
PODUSER=$3

# Check if required arguments are provided
if [ -z "$SLUG" ] || [ -z "$VERSION" ] || [ -z "$PODUSER" ]; then
    echo "Usage: $0 <slug> <version> <user>"
    exit 1
fi

podman build -t $SLUG:$VERSION .

cd /tmp # sudo preserves the current dirctory so use /tmp to avoid error
echo sudo podman image scp $USER@localhost:$SLUG:$VERSION $PODUSER@localhost::$SLUG:$VERSION
sudo podman image scp $USER@localhost::$SLUG:$VERSION $PODUSER@localhost::$SLUG:$VERSION
echo sudo -u $PODUSER podman tag $SLUG:$VERSION $SLUG:latest
sudo -u $PODUSER podman tag $SLUG:$VERSION $SLUG:latest


