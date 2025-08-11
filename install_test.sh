#!/bin/sh

# Install dependencies for wireless security testing and POSIX compliance tools
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
gcc || {
    echo "⚠️  Some packages failed to install - continuing with available tools"
    # Try alternative package names for CI compatibility
    sudo apt-get install -y wpa-supplicant || echo "ℹ️  wpa-supplicant not available in CI"
}

# Create virtual wireless interfaces for testing (skip if not available)
echo "ℹ️  Loading mac80211_hwsim kernel module..."
sudo modprobe mac80211_hwsim radios=3 2>/dev/null || echo "ℹ️  mac80211_hwsim kernel module not available (expected in CI environments)"

# Compile the C modules for default key calculation
echo "🔨 Compiling security modules..."
mkdir -p modules
if gcc -fomit-frame-pointer -O3 -funroll-all-loops -o modules/st src/stkeys.c -lcrypto 2>/dev/null; then
    echo "✅ ST module compiled successfully"
else
    echo "⚠️  Warning: Failed to compile ST module (may require additional libraries)"
    exit 1
fi

if gcc -O2 -o modules/upckeys src/upc_keys.c -lcrypto 2>/dev/null; then
    echo "✅ UPC module compiled successfully"
else
    echo "⚠️  Warning: Failed to compile UPC module (may require OpenSSL dev libraries)"
    exit 1
fi

if gcc -O3 -Wall -Wextra -o modules/wlanhc2hcx src/wlanhc2hcx.c 2>/dev/null; then
    echo "✅ wlanhc2hcx module compiled successfully"
else
    echo "⚠️  Warning: Failed to compile wlanhc2hcx module"
    exit 1
fi

# Run installation script with POSIX shell
sh install.sh
exit 0