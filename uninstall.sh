#!/bin/bash

# GX Tunnel - Uninstall Script
# Created by Jawad - Telegram: @jawadx

# Constants
INSTALL_DIR="/opt/gx_tunnel"
SYSTEMD_SERVICE_FILE="/etc/systemd/system/gx-tunnel.service"
WEBGUI_SERVICE_FILE="/etc/systemd/system/gx-webgui.service"
LOG_DIR="/var/log/gx_tunnel"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Function to display banner
display_banner() {
    echo -e "${BLUE}"
    echo -e "┌─────────────────────────────────────────────────────────┐"
    echo -e "│                    ${RED}🗑️ GX TUNNEL${BLUE}                          │"
    echo -e "│               ${YELLOW}Uninstall Script${BLUE}                       │"
    echo -e "└─────────────────────────────────────────────────────────┘"
    echo -e "${NC}"
}

# Function to print status messages
print_status() {
    echo -e "${BLUE}[*]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[+]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[-]${NC} $1"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Function to stop services
stop_services() {
    print_status "Stopping GX Tunnel services..."
    
    systemctl stop gx-tunnel 2>/dev/null
    systemctl stop gx-webgui 2>/dev/null
    
    print_success "Services stopped"
}

# Function to disable services
disable_services() {
    print_status "Disabling services..."
    
    systemctl disable gx-tunnel 2>/dev/null
    systemctl disable gx-webgui 2>/dev/null
    
    print_success "Services disabled"
}

# Function to remove systemd services
remove_services() {
    print_status "Removing systemd services..."
    
    rm -f $SYSTEMD_SERVICE_FILE
    rm -f $WEBGUI_SERVICE_FILE
    
    systemctl daemon-reload
    
    print_success "Systemd services removed"
}

# Function to remove installation directory
remove_installation_dir() {
    print_status "Removing installation directory..."
    
    if [ -d "$INSTALL_DIR" ]; then
        rm -rf $INSTALL_DIR
        print_success "Installation directory removed"
    else
        print_warning "Installation directory not found"
    fi
}

# Function to remove log directory
remove_log_dir() {
    print_status "Removing log directory..."
    
    if [ -d "$LOG_DIR" ]; then
        rm -rf $LOG_DIR
        print_success "Log directory removed"
    else
        print_warning "Log directory not found"
    fi
}

# Function to remove fail2ban configuration
remove_fail2ban_config() {
    print_status "Removing Fail2Ban configuration..."
    
    rm -f /etc/fail2ban/jail.d/gx-tunnel.conf
    rm -f /etc/fail2ban/filter.d/gx-tunnel.conf
    
    if systemctl is-active --quiet fail2ban; then
        systemctl reload fail2ban
    fi
    
    print_success "Fail2Ban configuration removed"
}

# Function to remove symlinks
remove_symlinks() {
    print_status "Removing symlinks..."
    
    rm -f /usr/local/bin/gxtunnel
    
    print_success "Symlinks removed"
}

# Function to show uninstall summary
show_summary() {
    echo
    echo -e "${GREEN}╔═══════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           🎯 UNINSTALLATION COMPLETE          ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${WHITE}The following components were removed:${NC}"
    echo -e "  ${RED}• GX Tunnel services${NC}"
    echo -e "  ${RED}• Web GUI interface${NC}"
    echo -e "  ${RED}• Installation directory${NC}"
    echo -e "  ${RED}• Log files${NC}"
    echo -e "  ${RED}• Fail2Ban configuration${NC}"
    echo -e "  ${RED}• Systemd service files${NC}"
    echo
    echo -e "${YELLOW}Note: User accounts created for tunneling were NOT removed.${NC}"
    echo -e "${YELLOW}You may want to manually remove them using 'userdel' command.${NC}"
    echo
}

# Main uninstall function
main() {
    display_banner
    
    print_warning "This will completely remove GX Tunnel from your system."
    echo
    read -p "Are you sure you want to continue? (y/N): " confirm
    
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        print_status "Uninstallation cancelled."
        exit 0
    fi
    
    # Check root privileges
    check_root
    
    # Stop services
    stop_services
    
    # Disable services
    disable_services
    
    # Remove systemd services
    remove_services
    
    # Remove installation directory
    remove_installation_dir
    
    # Remove log directory
    remove_log_dir
    
    # Remove fail2ban configuration
    remove_fail2ban_config
    
    # Remove symlinks
    remove_symlinks
    
    # Show summary
    show_summary
    
    print_success "GX Tunnel has been completely uninstalled from your system!"
}

# Run main function
main "$@"
