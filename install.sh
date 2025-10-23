#!/bin/bash

# GX Tunnel Complete Installation Script
# Created by Jawad - Telegram: @jawadx

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Constants
INSTALL_DIR="/opt/gx_tunnel"
LOG_DIR="/var/log/gx_tunnel"
SERVICE_NAME="gx-tunnel"
WEBGUI_SERVICE="gx-webgui"

# Beautiful banner function
display_banner() {
    echo -e "${BLUE}"
    echo -e "┌─────────────────────────────────────────────────────────┐"
    echo -e "│                    ${WHITE}🚀 GX TUNNEL${BLUE}                          │"
    echo -e "│           ${YELLOW}Advanced WebSocket SSH Tunnel${BLUE}                │"
    echo -e "│                                                         │"
    echo -e "│                 ${GREEN}🚀 Features:${BLUE}                            │"
    echo -e "│    ${GREEN}✅ Web GUI Admin${BLUE}       ${YELLOW}🌐 Real-time Stats${BLUE}          │"
    echo -e "│    ${CYAN}🔒 Fail2Ban Protection${BLUE}  ${PURPLE}⚡ Unlimited Bandwidth${BLUE}       │"
    echo -e "│                                                         │"
    echo -e "│              ${WHITE}Created by: Jawad${BLUE}                         │"
    echo -e "│           ${YELLOW}Telegram: @jawadx${BLUE}                           │"
    echo -e "└─────────────────────────────────────────────────────────┘"
    echo -e "${NC}"
}

# Progress banner function
show_progress_banner() {
    local step="$1"
    local description="$2"
    echo -e "${CYAN}"
    echo -e "┌─────────────────────────────────────────────────────────┐"
    echo -e "│   ${WHITE}🔄 [$step] ${YELLOW}$description${CYAN}"
    echo -e "└─────────────────────────────────────────────────────────┘"
    echo -e "${NC}"
}

# Success banner function
show_success_banner() {
    local message="$1"
    echo -e "${GREEN}"
    echo -e "┌─────────────────────────────────────────────────────────┐"
    echo -e "│   ${WHITE}✅ SUCCESS: ${GREEN}$message${GREEN}"
    echo -e "└─────────────────────────────────────────────────────────┘"
    echo -e "${NC}"
}

# Logging functions with pretty formatting
log_info() {
    echo -e "${BLUE}📦 [INFO]${NC} ${WHITE}$1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ [SUCCESS]${NC} ${WHITE}$1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️ [WARNING]${NC} ${WHITE}$1${NC}"
}

log_error() {
    echo -e "${RED}❌ [ERROR]${NC} ${WHITE}$1${NC}"
}

# Step indicator function
show_step() {
    local step_num="$1"
    local step_name="$2"
    echo -e "${PURPLE}✨ [Step $step_num] ${CYAN}$step_name${NC}"
}

# Check root with pretty output
check_root() {
    show_progress_banner "1" "Checking Privileges"
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        echo -e "${RED}Please run as: ${WHITE}sudo bash install.sh${NC}"
        exit 1
    fi
    log_success "Root privileges verified"
    echo
}

# Clean previous installation
clean_previous_installation() {
    show_progress_banner "2" "Cleaning Previous Installation"
    
    log_info "Stopping services..."
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl stop "$WEBGUI_SERVICE" 2>/dev/null || true
    
    log_info "Disabling services..."
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$WEBGUI_SERVICE" 2>/dev/null || true
    
    log_info "Removing service files..."
    rm -f /etc/systemd/system/"$SERVICE_NAME".service
    rm -f /etc/systemd/system/"$WEBGUI_SERVICE".service
    
    log_info "Removing directories..."
    rm -rf "$INSTALL_DIR"
    rm -rf "$LOG_DIR"
    
    log_info "Removing binary..."
    rm -f /usr/local/bin/gx-tunnel
    
    systemctl daemon-reload
    show_success_banner "Previous installation cleaned completely"
    echo
}

# Install system dependencies
install_dependencies() {
    show_progress_banner "3" "Installing System Dependencies"
    
    log_info "Updating package list..."
    apt-get update -qq
    
    log_info "Installing required packages..."
    apt-get install -y -qq \
        python3 \
        python3-pip \
        python3-venv \
        wget \
        curl \
        net-tools \
        sudo \
        ufw \
        jq \
        sqlite3 \
        fail2ban
    
    show_success_banner "All system dependencies installed"
    echo
}

# Install Python packages
install_python_packages() {
    show_progress_banner "4" "Installing Python Packages"
    
    log_info "Upgrading pip..."
    pip3 install --upgrade pip --quiet
    
    log_info "Installing Flask, Flask-CORS, and Psutil..."
    pip3 install flask flask-cors psutil --quiet
    
    show_success_banner "Python packages installed successfully"
    echo
}

# Create directory structure
create_directories() {
    show_progress_banner "5" "Creating Directory Structure"
    
    log_info "Creating installation directory..."
    mkdir -p "$INSTALL_DIR"
    
    log_info "Creating log directory..."
    mkdir -p "$LOG_DIR"
    
    chmod 755 "$INSTALL_DIR"
    chmod 755 "$LOG_DIR"
    
    show_success_banner "Directory structure created"
    echo
}

# Download application files
download_files() {
    show_progress_banner "6" "Downloading Application Files"
    
    local base_url="https://raw.githubusercontent.com/xcybermanx/GX_tunnel/main"
    
    log_info "Downloading main tunnel script..."
    wget -q "$base_url/gx_websocket.py" -O "$INSTALL_DIR/gx_websocket.py"
    
    log_info "Downloading web GUI script..."
    wget -q "$base_url/webgui.py" -O "$INSTALL_DIR/webgui.py"
    
    log_info "Downloading management script..."
    wget -q "$base_url/gx-tunnel.sh" -O /usr/local/bin/gx-tunnel
    chmod +x /usr/local/bin/gx-tunnel
    
    log_info "Creating users database..."
    cat > "$INSTALL_DIR/users.json" << 'EOF'
{
    "users": [],
    "settings": {
        "tunnel_port": 8080,
        "webgui_port": 8081,
        "admin_password": "admin123"
    }
}
EOF

    log_info "Creating statistics database..."
    touch "$INSTALL_DIR/statistics.db"
    
    show_success_banner "All application files downloaded"
    echo
}

# Create systemd services
create_services() {
    show_progress_banner "7" "Creating System Services"
    
    log_info "Creating tunnel service..."
    cat > /etc/systemd/system/"$SERVICE_NAME".service << EOF
[Unit]
Description=GX Tunnel WebSocket Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/python3 $INSTALL_DIR/gx_websocket.py
Restart=always
RestartSec=3
StandardOutput=append:$LOG_DIR/websocket.log
StandardError=append:$LOG_DIR/websocket.log

[Install]
WantedBy=multi-user.target
EOF

    log_info "Creating web GUI service..."
    cat > /etc/systemd/system/"$WEBGUI_SERVICE".service << EOF
[Unit]
Description=GX Tunnel Web GUI
After=network.target
Wants=$SERVICE_NAME.service

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/python3 $INSTALL_DIR/webgui.py
Restart=always
RestartSec=3
StandardOutput=append:$LOG_DIR/webgui.log
StandardError=append:$LOG_DIR/webgui.log

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    show_success_banner "Systemd services created and configured"
    echo
}

# Setup firewall
setup_firewall() {
    show_progress_banner "8" "Configuring Firewall"
    
    log_info "Enabling UFW firewall..."
    ufw --force enable > /dev/null 2>&1 || true
    
    log_info "Configuring firewall rules..."
    ufw allow 22/tcp comment 'SSH' > /dev/null 2>&1
    ufw allow 8080/tcp comment 'GX Tunnel' > /dev/null 2>&1
    ufw allow 8081/tcp comment 'GX Web GUI' > /dev/null 2>&1
    ufw allow 80/tcp comment 'HTTP' > /dev/null 2>&1
    ufw allow 443/tcp comment 'HTTPS' > /dev/null 2>&1
    
    show_success_banner "Firewall configured with all necessary ports"
    echo
}

# Setup fail2ban
setup_fail2ban() {
    show_progress_banner "9" "Setting Up Fail2Ban Protection"
    
    log_info "Configuring SSH protection..."
    cat > /etc/fail2ban/jail.d/sshd.local << EOF
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
EOF

    systemctl restart fail2ban
    show_success_banner "Fail2Ban protection activated"
    echo
}

# Verify installation
verify_installation() {
    show_progress_banner "10" "Verifying Installation"
    
    local errors=0
    
    log_info "Checking application files..."
    [ -f "$INSTALL_DIR/gx_websocket.py" ] || { log_error "Main tunnel script missing"; ((errors++)); }
    [ -f "$INSTALL_DIR/webgui.py" ] || { log_error "Web GUI script missing"; ((errors++)); }
    [ -f "/usr/local/bin/gx-tunnel" ] || { log_error "Management script missing"; ((errors++)); }
    [ -f "/etc/systemd/system/$SERVICE_NAME.service" ] || { log_error "Tunnel service missing"; ((errors++)); }
    [ -f "/etc/systemd/system/$WEBGUI_SERVICE.service" ] || { log_error "Web GUI service missing"; ((errors++)); }
    
    log_info "Checking Python packages..."
    python3 -c "import flask, flask_cors, psutil" > /dev/null 2>&1 || { 
        log_error "Python packages not installed properly"; 
        ((errors++)); 
    }
    
    if [ $errors -eq 0 ]; then
        show_success_banner "Installation verified successfully"
        return 0
    else
        log_error "Installation verification failed with $errors errors"
        return 1
    fi
}

# Start services
start_services() {
    show_progress_banner "11" "Starting Services"
    
    log_info "Enabling services..."
    systemctl enable "$SERVICE_NAME" "$WEBGUI_SERVICE"
    
    log_info "Starting services..."
    systemctl start "$SERVICE_NAME" "$WEBGUI_SERVICE"
    
    sleep 3
    
    local tunnel_status=$(systemctl is-active "$SERVICE_NAME")
    local webgui_status=$(systemctl is-active "$WEBGUI_SERVICE")
    
    if [ "$tunnel_status" = "active" ] && [ "$webgui_status" = "active" ]; then
        show_success_banner "All services started successfully"
        return 0
    else
        log_warning "Services partially started (Tunnel: $tunnel_status, WebGUI: $webgui_status)"
        return 1
    fi
}

# Beautiful installation summary
show_installation_summary() {
    local server_ip=$(hostname -I | awk '{print $1}')
    
    echo
    echo -e "${GREEN}"
    echo -e "┌─────────────────────────────────────────────────────────┐"
    echo -e "│                  🎉 INSTALLATION COMPLETE!              │"
    echo -e "└─────────────────────────────────────────────────────────┘"
    echo -e "${NC}"
    echo
    echo -e "${WHITE}📋 ${CYAN}Installation Details:${NC}"
    echo -e "  ${BLUE}└─ ${YELLOW}Installation: ${GREEN}$INSTALL_DIR${NC}"
    echo -e "  ${BLUE}└─ ${YELLOW}Logs: ${GREEN}$LOG_DIR${NC}"
    echo -e "  ${BLUE}└─ ${YELLOW}Management: ${GREEN}gx-tunnel${NC}"
    echo
    echo -e "${WHITE}🌐 ${CYAN}Access Information:${NC}"
    echo -e "  ${BLUE}└─ ${YELLOW}Tunnel: ${GREEN}ws://$server_ip:8080${NC}"
    echo -e "  ${BLUE}└─ ${YELLOW}Web GUI: ${GREEN}http://$server_ip:8081${NC}"
    echo -e "  ${BLUE}└─ ${YELLOW}Admin Password: ${GREEN}admin123${NC}"
    echo
    echo -e "${WHITE}🚀 ${CYAN}Available Commands:${NC}"
    echo -e "  ${GREEN}└─ gx-tunnel menu${NC}       - Show interactive menu"
    echo -e "  ${GREEN}└─ gx-tunnel start${NC}      - Start services"
    echo -e "  ${GREEN}└─ gx-tunnel status${NC}     - Show service status"
    echo -e "  ${GREEN}└─ gx-tunnel add-user${NC}   - Add tunnel user"
    echo -e "  ${GREEN}└─ gx-tunnel list-users${NC} - List all users"
    echo
    echo -e "${WHITE}⏰ ${CYAN}Next Steps:${NC}"
    echo -e "  ${BLUE}1. ${YELLOW}Access Web GUI: ${GREEN}http://$server_ip:8081${NC}"
    echo -e "  ${BLUE}2. ${YELLOW}Add user: ${GREEN}gx-tunnel add-user${NC}"
    echo -e "  ${BLUE}3. ${YELLOW}Check status: ${GREEN}gx-tunnel status${NC}"
    echo
    echo -e "${PURPLE}💫 ${WHITE}Thank you for choosing GX Tunnel!${NC}"
    echo
}

# Main installation function
main() {
    display_banner
    echo
    echo -e "${GREEN}🚀 [GX TUNNEL] Starting installation...${NC}"
    echo
    
    # Execute installation steps
    check_root
    clean_previous_installation
    install_dependencies
    install_python_packages
    create_directories
    download_files
    create_services
    setup_firewall
    setup_fail2ban
    
    # Verify and start
    if verify_installation; then
        start_services
        show_installation_summary
    else
        echo -e "${RED}"
        echo -e "┌─────────────────────────────────────────────────────────┐"
        echo -e "│                   ❌ INSTALLATION FAILED!                │"
        echo -e "└─────────────────────────────────────────────────────────┘"
        echo -e "${NC}"
        log_error "Please check the errors above and try again"
        exit 1
    fi
}

# Run main function
main "$@"
