#!/bin/bash
# build.sh - ZDB.COM (requiere zmac; ver LEEME.md)
set -e
cd "$(dirname "$0")"
ZMAC=${ZMAC:-zmac} python3 mkzdb.py
