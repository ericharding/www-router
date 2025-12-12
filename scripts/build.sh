#!/bin/bash

set -e

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

