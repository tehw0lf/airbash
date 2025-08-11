#!/bin/bash

# Docker-based WiFi Simulation for Airbash Testing
# This script sets up a virtual WiFi environment using the linuxkit-mac80211_hwsim Docker container
# and provides utilities for testing airbash functionality

set -e

# Configuration
CONTAINER_NAME="airbash-hwsim"
DOCKER_IMAGE="singelet/linuxkit-mac80211_hwsim:latest"
NETWORK_NAMESPACE="airbash_test"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

check_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is not installed or not in PATH"
        return 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon is not running or accessible"
        return 1
    fi
    
    log_success "Docker is available and running"
    return 0
}

pull_hwsim_image() {
    log_info "Pulling mac80211_hwsim Docker image..."
    if docker pull "$DOCKER_IMAGE"; then
        log_success "Successfully pulled $DOCKER_IMAGE"
        return 0
    else
        log_error "Failed to pull Docker image"
        return 1
    fi
}

start_hwsim_container() {
    log_info "Starting WiFi simulation container..."
    
    # Stop existing container if running
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
    
    # Start the container with necessary capabilities and volumes
    if docker run --rm -d \
        --name "$CONTAINER_NAME" \
        --privileged \
        --cap-add CAP_SYS_MODULE \
        --cap-add CAP_NET_ADMIN \
        --cap-add CAP_SYS_ADMIN \
        -v /lib/modules:/lib/modules:ro \
        -v /sys/kernel:/sys/kernel \
        "$DOCKER_IMAGE" sleep 3600; then
        
        log_success "WiFi simulation container started"
        
        # Wait for the container to initialize
        sleep 5
        
        # Check if hwsim interfaces are available
        if docker exec "$CONTAINER_NAME" iw dev 2>/dev/null | grep -q "Interface wlan"; then
            log_success "Virtual WiFi interfaces detected in container"
            return 0
        else
            log_warning "No virtual WiFi interfaces detected, checking module status..."
            docker exec "$CONTAINER_NAME" lsmod | grep mac80211 || true
            return 1
        fi
    else
        log_error "Failed to start WiFi simulation container"
        return 1
    fi
}

setup_network_namespace() {
    log_info "Setting up network namespace for testing..."
    
    # Create network namespace
    sudo ip netns add "$NETWORK_NAMESPACE" 2>/dev/null || {
        log_warning "Network namespace $NETWORK_NAMESPACE already exists, cleaning up..."
        sudo ip netns delete "$NETWORK_NAMESPACE" 2>/dev/null || true
        sudo ip netns add "$NETWORK_NAMESPACE"
    }
    
    # Set up loopback interface
    sudo ip netns exec "$NETWORK_NAMESPACE" ip link set lo up
    
    log_success "Network namespace $NETWORK_NAMESPACE created"
}

create_virtual_interfaces() {
    log_info "Creating virtual WiFi interfaces..."
    
    # Create virtual interfaces using the Docker container
    docker exec "$CONTAINER_NAME" sh -c '
        # Load mac80211_hwsim if not already loaded
        if ! lsmod | grep -q mac80211_hwsim; then
            modprobe mac80211_hwsim radios=3 2>/dev/null || echo "Module may already be loaded"
        fi
        
        # Wait for interfaces to appear
        sleep 2
        
        # List available interfaces
        echo "Available interfaces:"
        iw dev 2>/dev/null || ip link show | grep wlan || echo "No wireless interfaces found"
    '
    
    # Copy interfaces to host network namespace if possible
    # Note: This is a simplified approach - in practice, you might need more complex network setup
    log_info "Virtual interfaces setup completed in container"
}

setup_test_environment() {
    log_info "Setting up complete test environment..."
    
    check_docker || return 1
    pull_hwsim_image || return 1
    start_hwsim_container || return 1
    setup_network_namespace || return 1
    create_virtual_interfaces || return 1
    
    log_success "WiFi simulation environment is ready!"
    
    # Display container status
    echo ""
    log_info "Container Status:"
    docker ps --filter "name=$CONTAINER_NAME" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    
    echo ""
    log_info "Available interfaces in container:"
    docker exec "$CONTAINER_NAME" iw dev 2>/dev/null || echo "No wireless interfaces detected"
    
    return 0
}

run_in_container() {
    if [ $# -eq 0 ]; then
        log_error "No command specified to run in container"
        return 1
    fi
    
    log_info "Executing in container: $*"
    docker exec -it "$CONTAINER_NAME" "$@"
}

cleanup() {
    log_info "Cleaning up WiFi simulation environment..."
    
    # Stop and remove container
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
    
    # Remove network namespace
    sudo ip netns delete "$NETWORK_NAMESPACE" 2>/dev/null || true
    
    log_success "Cleanup completed"
}

show_status() {
    echo "=== WiFi Simulation Status ==="
    
    echo "Container Status:"
    if docker ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "$CONTAINER_NAME"; then
        log_success "Container $CONTAINER_NAME is running"
        docker exec "$CONTAINER_NAME" iw dev 2>/dev/null || echo "No wireless interfaces detected"
    else
        log_warning "Container $CONTAINER_NAME is not running"
    fi
    
    echo ""
    echo "Network Namespace:"
    if sudo ip netns list | grep -q "$NETWORK_NAMESPACE"; then
        log_success "Network namespace $NETWORK_NAMESPACE exists"
    else
        log_warning "Network namespace $NETWORK_NAMESPACE does not exist"
    fi
}

# Main command handling
case "${1:-help}" in
    "setup"|"start")
        setup_test_environment
        ;;
    "stop"|"cleanup")
        cleanup
        ;;
    "status")
        show_status
        ;;
    "shell")
        run_in_container /bin/sh
        ;;
    "exec")
        shift
        run_in_container "$@"
        ;;
    "help"|*)
        echo "WiFi Simulation Docker Manager"
        echo "Usage: $0 {setup|stop|status|shell|exec|help}"
        echo ""
        echo "Commands:"
        echo "  setup    - Set up the complete WiFi simulation environment"
        echo "  stop     - Stop and cleanup the simulation environment"  
        echo "  status   - Show current status of simulation environment"
        echo "  shell    - Open a shell in the simulation container"
        echo "  exec CMD - Execute command in the simulation container"
        echo "  help     - Show this help message"
        echo ""
        echo "Examples:"
        echo "  $0 setup"
        echo "  $0 exec iw dev"
        echo "  $0 shell"
        echo "  $0 stop"
        ;;
esac