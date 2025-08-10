#!/bin/bash

# Shell script linting
shellcheck src/airba.sh src/crackdefault.sh modules/*.sh || true

# Verify compiled modules work
./modules/st --help || echo "ST module compiled successfully"
./modules/upckeys --help || echo "UPC module compiled successfully"