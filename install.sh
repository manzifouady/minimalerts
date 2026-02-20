#!/bin/bash

# Server Health Monitor Installation Script
# This script automatically installs and configures the server health monitor

set -e  # Exit on any error

echo "🚀 Server Health Monitor Installation"
echo "====================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="/root/server-alerts"
SERVICE_NAME="server-health-monitor"
VENV_DIR="$INSTALL_DIR/.venv"

# Function to print colored output
print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root (sudo)"
    exit 1
fi

# Check if we're in the correct directory
if [[ ! -f "monitor.py" ]] || [[ ! -f "config.sample.json" ]]; then
    print_error "Please run this script from the server-alerts directory"
    print_info "Expected files: monitor.py, config.sample.json"
    exit 1
fi

print_info "Starting installation..."

# Step 1: Copy configuration file
if [[ ! -f "config.json" ]]; then
    print_info "Creating configuration file..."
    cp config.sample.json config.json
    print_status "Configuration file created: config.json"
    print_warning "Please edit config.json with your email/SMS credentials before proceeding"
    read -p "Press Enter after editing config.json to continue..."
else
    print_status "Configuration file already exists"
fi

# Step 2: Create virtual environment
if [[ ! -d ".venv" ]]; then
    print_info "Creating Python virtual environment..."
    python3 -m venv .venv
    print_status "Virtual environment created"
else
    print_status "Virtual environment already exists"
fi

# Step 3: Install dependencies
print_info "Installing Python dependencies..."
.venv/bin/pip install --upgrade pip > /dev/null 2>&1
.venv/bin/pip install -r requirements.txt > /dev/null 2>&1
print_status "Dependencies installed"

# Step 4: Set permissions
print_info "Setting file permissions..."
chmod 600 config.json
chmod 755 monitor.py
chmod 755 install.sh
print_status "Permissions set"

# Step 5: Install systemd service and timer
print_info "Installing systemd service and timer..."

# Copy service file
cp server-health-monitor.service /etc/systemd/system/
cp server-health-monitor.timer /etc/systemd/system/

# Reload systemd daemon
systemctl daemon-reload

# Enable and start the timer
systemctl enable server-health-monitor.timer
systemctl start server-health-monitor.timer

print_status "Systemd service and timer installed and started"

# Step 6: Test the installation
print_info "Testing installation..."
if .venv/bin/python monitor.py --self-test > /dev/null 2>&1; then
    print_status "Installation test passed"
else
    print_error "Installation test failed"
    exit 1
fi

# Step 7: Show status
echo ""
print_status "Installation completed successfully!"
echo ""
echo "📊 Service Status:"
echo "  Timer: $(systemctl is-active server-health-monitor.timer)"
echo "  Next run: $(systemctl list-timers server-health-monitor.timer --no-pager | grep server-health-monitor.timer | awk '{print $5,$6,$7,$8,$9}')"
echo ""
echo "🔧 Useful Commands:"
echo "  Check status: systemctl status server-health-monitor.timer"
echo "  View logs: journalctl -u server-health-monitor.service -f"
echo "  Test manually: $INSTALL_DIR/.venv/bin/python $INSTALL_DIR/monitor.py --run-once"
echo "  Send test alert: $INSTALL_DIR/.venv/bin/python $INSTALL_DIR/monitor.py --test-alert"
echo ""
echo "⚙️  Configuration:"
echo "  Config file: $INSTALL_DIR/config.json"
echo "  Edit this file to change thresholds, recipients, or credentials"
echo ""
print_warning "Don't forget to edit $INSTALL_DIR/config.json with your actual credentials!"
echo ""
print_info "The monitor will run every 5 minutes automatically."