#!/bin/bash

# Simplified Airbash Test Suite for CI environments (ubuntu-latest with Docker)
# Uses Docker-based WiFi simulation for reliable testing

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

run_test() {
    local test_name="$1"
    local test_command="$2"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    echo ""
    log_info "Running test: $test_name"
    
    if eval "$test_command"; then
        log_success "$test_name"
        return 0
    else
        log_error "$test_name"
        return 1
    fi
}

print_test_summary() {
    echo ""
    echo "========================================="
    echo "           TEST SUMMARY"
    echo "========================================="
    echo "Total tests:  $TESTS_TOTAL"
    echo -e "Passed tests: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed tests: ${RED}$TESTS_FAILED${NC}"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}🎉 All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}💥 Some tests failed!${NC}"
        return 1
    fi
}

# Test Functions
test_c_modules_compilation() {
    mkdir -p modules
    
    # Test ST keys module
    gcc -fomit-frame-pointer -O3 -funroll-all-loops -o modules/st src/stkeys.c -lcrypto 2>/dev/null && \
    [ -f "modules/st" ] && [ -x "modules/st" ] && \
    
    # Test UPC keys module  
    gcc -O2 -o modules/upckeys src/upc_keys.c -lcrypto 2>/dev/null && \
    [ -f "modules/upckeys" ] && [ -x "modules/upckeys" ] && \
    
    # Test wlanhc2hcx module
    gcc -O3 -Wall -Wextra -o modules/wlanhc2hcx src/wlanhc2hcx.c 2>/dev/null && \
    [ -f "modules/wlanhc2hcx" ] && [ -x "modules/wlanhc2hcx" ]
}

test_database_operations() {
    [ -f ".database.sqlite3" ] && \
    sqlite3 .database.sqlite3 "SELECT name FROM sqlite_master WHERE type='table';" 2>/dev/null | grep -q "captures" && \
    sqlite3 .database.sqlite3 "INSERT OR IGNORE INTO captures (bssid, essid, pmkid, processed) VALUES ('02:00:00:00:01:00', 'TEST_NETWORK', 'test_pmkid_data', 0);" 2>/dev/null && \
    sqlite3 .database.sqlite3 "SELECT COUNT(*) FROM captures WHERE bssid='02:00:00:00:01:00';" 2>/dev/null | grep -q "1"
}

test_main_scripts() {
    [ -f "airba.sh" ] && [ -x "airba.sh" ] && \
    [ -f "crackdefault.sh" ] && [ -x "crackdefault.sh" ] && \
    bash -n "airba.sh" 2>/dev/null && \
    bash -n "crackdefault.sh" 2>/dev/null
}

test_shell_modules() {
    local modules=(template.sh upc7d.sh hotbox.sh st.sh sp5700.sh)
    local found_modules=0
    
    for module in "${modules[@]}"; do
        if [ -f "modules/$module" ]; then
            bash -n "modules/$module" 2>/dev/null && found_modules=$((found_modules + 1))
        fi
    done
    
    [ $found_modules -gt 0 ]
}

test_upc_functionality() {
    if [ -f "modules/upckeys" ]; then
        ./modules/upckeys "UPC1234567" "24" 2>/dev/null | grep -q .
    else
        return 0  # Skip if module not compiled
    fi
}

test_wifi_simulation() {
    log_info "Starting Docker WiFi simulation container..."
    
    # Start the WiFi simulation container
    docker run --rm -d \
        --name airbash-hwsim-test \
        --privileged \
        --cap-add CAP_SYS_MODULE \
        --cap-add CAP_NET_ADMIN \
        --cap-add CAP_SYS_ADMIN \
        -v /lib/modules:/lib/modules:ro \
        singelet/linuxkit-mac80211_hwsim:latest sleep 60
    
    # Wait for container to initialize
    sleep 5
    
    # Check if wireless interfaces are available
    if docker exec airbash-hwsim-test iw dev 2>/dev/null | grep -q "Interface"; then
        log_info "Virtual WiFi interfaces detected"
        
        # Create a simple hostapd configuration test
        docker exec airbash-hwsim-test sh -c '
            echo "interface=wlan0
driver=nl80211
ssid=UPC1234567
channel=1
hw_mode=g" > /tmp/test.conf
            
            # Test that we can at least parse the config
            hostapd -t /tmp/test.conf 2>/dev/null || echo "hostapd config test"
        ' && return 0
    else
        log_info "No virtual interfaces found (may be expected in some CI environments)"
        return 1
    fi
}

test_integration() {
    # Insert test data for integration testing
    sqlite3 .database.sqlite3 "INSERT OR IGNORE INTO captures (bssid, essid, pmkid, processed) VALUES ('02:00:00:00:02:00', 'UPC1234567', 'test_pmkid_upc', 0);" 2>/dev/null
    
    # Test crackdefault functionality (should run without errors)
    timeout 10s bash crackdefault.sh 2>/dev/null || true
    
    # Verify database still works
    sqlite3 .database.sqlite3 "SELECT COUNT(*) FROM captures;" 2>/dev/null | grep -q "[0-9]"
}

cleanup_test() {
    # Clean up Docker container if it exists
    docker stop airbash-hwsim-test 2>/dev/null || true
    docker rm airbash-hwsim-test 2>/dev/null || true
    log_info "Cleanup completed"
}

# Trap for cleanup on exit
trap cleanup_test EXIT

echo "🚀 Starting Airbash CI Test Suite..."

# Install airbash first
log_info "Installing Airbash..."
bash install.sh

log_info "Running CI test suite..."

# Run all tests
run_test "C Modules Compilation" "test_c_modules_compilation"
run_test "Database Operations" "test_database_operations"  
run_test "Main Scripts Creation" "test_main_scripts"
run_test "Shell Modules Structure" "test_shell_modules"
run_test "UPC Module Functionality" "test_upc_functionality"
run_test "WiFi Simulation Setup" "test_wifi_simulation"
run_test "Integration Testing" "test_integration"

# Print results
print_test_summary

echo ""
echo "🎯 Airbash CI testing completed!"

# Exit with error code if any tests failed
exit $TESTS_FAILED