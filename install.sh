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

# Step 1: Configuration Setup
if [[ ! -f "config.json" ]]; then
    print_info "Setting up configuration..."
    cp config.sample.json config.json

    echo ""
    echo "📧 EMAIL CONFIGURATION SETUP"
    echo "============================"
    echo ""
    echo "The monitoring system needs email configuration to send alerts."
    echo "We'll help you set up Gmail (recommended) or another SMTP provider."
    echo ""
    echo "🔑 For Gmail Setup:"
    echo "1. Go to https://myaccount.google.com/security"
    echo "2. Enable 2-Factor Authentication"
    echo "3. Go to 'App passwords' section"
    echo "4. Generate a new app password for 'Mail'"
    echo "5. Use your Gmail address and the 16-character app password below"
    echo ""

    # Get email configuration interactively
    read -p "Enter your Gmail address (e.g., your-email@gmail.com): " user_email
    while [[ -z "$user_email" ]] || [[ "$user_email" != *"@"* ]]; do
        echo "Please enter a valid email address."
        read -p "Enter your Gmail address: " user_email
    done

    read -s -p "Enter your Gmail App Password (16 characters, no spaces): " app_password
    echo ""
    while [[ -z "$app_password" ]] || [[ ${#app_password} -ne 16 ]]; do
        echo "App password should be 16 characters. Please check your Gmail app password."
        read -s -p "Enter your Gmail App Password: " app_password
        echo ""
    done

    echo ""
    read -p "Enter recipient email addresses (comma-separated): " recipients_input
    IFS=',' read -ra recipients_array <<< "$recipients_input"
    recipients_json=$(printf '%s\n' "${recipients_array[@]}" | jq -R . | jq -s .)

    # Update config.json with user input
    jq --arg email "$user_email" \
       --arg password "$app_password" \
       --argjson recipients "$recipients_json" \
       '.email.host_user = $email | .email.host_password = $password | .email.recipients = $recipients' \
       config.json > config.tmp && mv config.tmp config.json

    print_status "Email configuration saved to config.json"

    echo ""
    echo "📱 OPTIONAL: SMS CONFIGURATION"
    echo "=============================="
    echo ""
    read -p "Do you want to configure SMS alerts? (y/n): " setup_sms
    if [[ $setup_sms =~ ^[Yy]$ ]]; then
        echo ""
        echo "For SMS setup, you need:"
        echo "- IPPanel API Key (get from https://ippanel.com)"
        echo "- Pattern Code (create a pattern in IPPanel dashboard)"
        echo "- Sender Number (your IPPanel number)"
        echo ""

        read -p "Enter IPPanel API Key: " api_key
        read -p "Enter Pattern Code: " pattern_code
        read -p "Enter Sender Number (e.g., +983000505): " sender_number
        read -p "Enter SMS recipient phone numbers (comma-separated, e.g., +989xxxxxxxxx): " sms_recipients_input

        IFS=',' read -ra sms_recipients_array <<< "$sms_recipients_input"
        sms_recipients_json=$(printf '%s\n' "${sms_recipients_array[@]}" | jq -R . | jq -s .)

        # Update SMS config and enable it
        jq --arg api_key "$api_key" \
           --arg pattern_code "$pattern_code" \
           --arg sender_number "$sender_number" \
           --argjson sms_recipients "$sms_recipients_json" \
           '.sms.enabled = true | .sms.api_key = $api_key | .sms.pattern_code = $pattern_code | .sms.sender_number = $sender_number | .sms.recipients = $sms_recipients' \
           config.json > config.tmp && mv config.tmp config.json

        print_status "SMS configuration enabled and saved"
    else
        print_info "SMS configuration skipped (can be enabled later by editing config.json)"
    fi

    echo ""
    echo "⚙️  THRESHOLDS CONFIGURATION"
    echo "==========================="
    echo ""
    read -p "Use default monitoring thresholds? (y/n): " use_defaults
    if [[ ! $use_defaults =~ ^[Yy]$ ]]; then
        echo ""
        echo "Current defaults:"
        echo "- CPU busy %: 90"
        echo "- Memory available MB: 2048"
        echo "- Disk used %: 90"
        echo ""

        read -p "Enter CPU busy threshold % (default 90): " cpu_threshold
        cpu_threshold=${cpu_threshold:-90}

        read -p "Enter minimum available memory MB (default 2048): " mem_threshold
        mem_threshold=${mem_threshold:-2048}

        read -p "Enter maximum disk usage % (default 90): " disk_threshold
        disk_threshold=${disk_threshold:-90}

        # Update thresholds
        jq --arg cpu "$cpu_threshold" \
           --arg mem "$mem_threshold" \
           --arg disk "$disk_threshold" \
           '.thresholds.cpu_busy_percent = ($cpu | tonumber) | .thresholds.mem_available_mb = ($mem | tonumber) | .thresholds.disk_used_percent = ($disk | tonumber)' \
           config.json > config.tmp && mv config.tmp config.json

        print_status "Custom thresholds saved"
    fi

    echo ""
    print_status "Configuration completed!"

else
    print_status "Configuration file already exists"
    print_warning "If you need to reconfigure, delete config.json and run install.sh again"
fi

# Step 2: Create virtual environment
if [[ ! -d ".venv" ]]; then
    print_info "Creating Python virtual environment..."
    python3 -m venv .venv
    print_status "Virtual environment created"
else
    print_status "Virtual environment already exists"
fi

# Step 3: Install system dependencies
print_info "Installing system dependencies..."
if ! command -v jq &> /dev/null; then
    if command -v apt-get &> /dev/null; then
        apt-get update > /dev/null 2>&1 && apt-get install -y jq > /dev/null 2>&1
    elif command -v yum &> /dev/null; then
        yum install -y jq > /dev/null 2>&1
    else
        print_error "Could not install jq. Please install jq manually and run install.sh again."
        exit 1
    fi
    print_status "jq installed"
else
    print_status "jq already installed"
fi

# Step 4: Install Python dependencies
print_info "Installing Python dependencies..."
.venv/bin/pip install --upgrade pip > /dev/null 2>&1
.venv/bin/pip install -r requirements.txt > /dev/null 2>&1
print_status "Python dependencies installed"

# Step 5: Set permissions
print_info "Setting file permissions..."
chmod 600 config.json
chmod 755 monitor.py
chmod 755 install.sh
print_status "Permissions set"

# Step 6: Validate configuration
print_info "Validating configuration..."
if .venv/bin/python monitor.py --self-test > /dev/null 2>&1; then
    print_status "Configuration validation passed"
else
    print_error "Configuration validation failed"
    print_warning "Please check your config.json file and run install.sh again"
    exit 1
fi

# Step 7: Test email configuration
print_info "Testing email configuration..."
echo ""
read -p "Do you want to send a test email to verify configuration? (y/n): " test_email
if [[ $test_email =~ ^[Yy]$ ]]; then
    if .venv/bin/python monitor.py --test-alert > /dev/null 2>&1; then
        print_status "Test email sent successfully!"
        echo ""
        print_info "Check your inbox for the test alert email."
        read -p "Did you receive the test email? (y/n): " email_received
        if [[ ! $email_received =~ ^[Yy]$ ]]; then
            print_error "Email test failed. Please check your configuration."
            print_warning "You can reconfigure by deleting config.json and running install.sh again"
            exit 1
        fi
    else
        print_error "Failed to send test email. Please check your email configuration."
        print_warning "Common issues:"
        echo "  - Wrong Gmail App Password"
        echo "  - 2FA not enabled on Gmail"
        echo "  - Firewall blocking SMTP"
        exit 1
    fi
else
    print_info "Email test skipped"
fi

# Step 8: Install systemd services
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

# Step 9: Show status
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