#!/bin/bash

set -e

SLUG=$1
VERSION=$2
PODUSER=$3

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

if [ -z "$PODUSER" ]; then
    echo "Error: PODUSER argument is required"
    echo "Usage: $0 <slug> <version> <user>"
    exit 1
fi

podman build -t $SLUG:$VERSION .

cd /tmp # sudo preserves the current dirctory so use /tmp to avoid error
sudo podman image scp $USER@localhost:$SLUG:$VERSION $PODUSER@localhost::$SLUG:$VERSION
sudo -u $PODUSER podman tag $SLUG:$VERSION $SLUG:latest


