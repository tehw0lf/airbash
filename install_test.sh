#!/bin/bash

# Install dependencies for wireless security testing
sudo apt-get update
sudo apt-get install -y \
aircrack-ng \
hcxtools \
sqlite3 \
openssl \
libssl-dev \
hostapd \
wpasupplicant \
iw \
net-tools \
build-essential \
gcc

# Create virtual wireless interfaces for testing
sudo modprobe mac80211_hwsim radios=3

# Compile the C modules for default key calculation
gcc -fomit-frame-pointer -O3 -funroll-all-loops -o modules/st src/stkeys.c -lcrypto
gcc -O2 -o modules/upckeys src/upc_keys.c -lcrypto

# Run installation script
bash install.sh