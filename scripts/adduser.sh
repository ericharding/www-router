#!/bin/bash

set -e

PODUSERNAME=$1

# Check if required arguments are provided
if [ -z "$PODUSERNAME" ]; then
    echo "Error: PODUSERNAME argument is required"
    echo "Usage: $0 <username> <userid>"
    exit 1
fi

ID=$(cat users.txt | wc -l)
PODUSERID=$(($ID + 10000))
echo $PODUSERNAME $PODUSERID
read -p "hit enter to continue"

sudo useradd -u $PODUSERID -m -s /sbin/nologin $PODUSERNAME &&
  sudo loginctl enable-linger $PODUSERNAME &&
  echo 'export XDG_RUNTIME_DIR=/run/user/$(id -u)' | sudo tee -a /home/$PODUSERNAME/.bashrc > /dev/null &&
  echo $PODUSERNAME $PODUSERID >> users.txt &&
  tail -n 1 users.txt

# To enable login shell for a user: sudo usermod -s /bin/bash $PODUSERNAME


