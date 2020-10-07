#!/usr/bin/env bash

set -e

echo Kernel version: $(uname -r)
echo Updating...

wget https://raw.githubusercontent.com/pimlie/ubuntu-mainline-kernel.sh/master/ubuntu-mainline-kernel.sh
chmod +x ubuntu-mainline-kernel.sh
./ubuntu-mainline-kernel.sh --yes

echo Kernel version: $(uname -r)
