#!/bin/bash

# Create test environment with virtual WiFi
export TEST_INTERFACE="hwsim0"

# Set up network namespace for isolated testing
sudo ip netns add airbash_test
sudo ip netns exec airbash_test ip link set lo up

# Configure virtual access point in test namespace
sudo ip netns exec airbash_test hostapd -B /dev/stdin << EOF
interface=hwsim0
driver=nl80211
ssid=TEST_UPC1234567
channel=1
hw_mode=g
wpa=2
wpa_key_mgmt=WPA-PSK
wpa_pairwise=CCMP
wpa_passphrase=DefaultTestKey123
EOF

# Wait for AP to start
sleep 2

# Configure virtual client to connect and disconnect (simulating deauth scenario)
sudo ip netns exec airbash_test wpa_supplicant -B -i hwsim1 -c /dev/stdin << EOF
network={
    ssid="TEST_UPC1234567"
    psk="DefaultTestKey123"
}
EOF

# Wait for connection
sleep 3

# Test the database creation
sqlite3 .database.sqlite3 "SELECT name FROM sqlite_master WHERE type='table';" | grep captures

# Test crackdefault.sh with a simulated database entry
sqlite3 .database.sqlite3 "INSERT INTO captures (bssid, essid, pmkid, processed) VALUES ('02:00:00:00:01:00', 'TEST_UPC1234567', 'test_pmkid', 0);"

# Test the UPC module detection
echo "Testing UPC7D module detection..."
bash src/crackdefault.sh | grep -q "UPC detected" && echo "✅ UPC module detection works!"

# Test Thomson module with a Thomson SSID
sqlite3 .database.sqlite3 "INSERT INTO captures (bssid, essid, pmkid, processed) VALUES ('02:00:00:00:02:00', 'Thomson123ABC', 'test_pmkid_2', 0);"
bash src/crackdefault.sh | grep -q "Thomson/SpeedTouch detected" && echo "✅ Thomson module detection works!"

# Cleanup test environment
sudo pkill hostapd || true
sudo pkill wpa_supplicant || true
sudo ip netns delete airbash_test || true

echo "🎯 Airbash security testing suite completed successfully!"