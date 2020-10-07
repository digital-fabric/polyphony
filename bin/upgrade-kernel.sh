#!/usr/bin/env bash

set -e

echo Kernel version: $(uname -r)
echo Updating...

wget https://ksplice.oracle.com/uptrack/dist/focal/uptrack.deb
sudo apt install ./uptrack.deb
sudo uptrack-upgrade -y

echo Kernel version: $(uname -r)
