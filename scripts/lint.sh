#!/usr/bin/env bash
# Lint all Vim script with vint (https://github.com/Kuniwak/vint).
# Install: pip install vim-vint
set -u
cd "$(dirname "$0")/.."
exec vint .
