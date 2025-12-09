#!/bin/bash

set -e

SLUG=$1
VERSION=$2

podman build -t $SLUG:$VERSION .

sudo podman image scp $USER@localhost::$SLUG:$VERSION
sudo podman tag $SLUG:$VERSION $SLUG:latest

