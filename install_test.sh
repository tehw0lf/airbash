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

# Set up Docker-based wireless simulation for CI environments
echo "🔧 Setting up Docker-based wireless simulation for CI..."

# Ensure Docker is available (required for CI testing)
if ! command -v docker >/dev/null 2>&1; then
    echo "❌ Docker is required for CI testing but not found"
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker daemon is not accessible"
    exit 1
fi

echo "✅ Docker detected - setting up WiFi simulation"

# Pull the WiFi simulation Docker image
echo "📥 Pulling WiFi simulation Docker image..."
docker pull singelet/linuxkit-mac80211_hwsim:latest

echo "✅ WiFi simulation environment ready for CI testing"

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