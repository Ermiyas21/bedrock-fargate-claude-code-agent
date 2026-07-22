#!/bin/bash
# Simple healthcheck to verify the container has required tools
set -e

node --version > /dev/null 2>&1
git --version > /dev/null 2>&1
gh --version > /dev/null 2>&1
aws --version > /dev/null 2>&1
claude --version > /dev/null 2>&1

echo "All tools available."
