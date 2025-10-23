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

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Banner
show_banner() {
    echo -e "${BLUE}"
    echo -e "┌─────────────────────────────────────────────────────────┐"
    echo -e "│                    ${WHITE}🚀 GX TUNNEL${BLUE}                          │"
    echo -e "│           ${YELLOW}Complete Installation Script${BLUE}                 │"
    echo -e "│                                                         │"
    echo -e "│              ${WHITE}Created by: Jawad${BLUE}                         │"
    echo -e "│           ${YELLOW}Telegram: @jawadx${BLUE}                           │"
    echo -e "└─────────────────────────────────────────────────────────┘"
    echo -e "${NC}"
}

# Check root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
    log_success "Running as root user"
}

# Clean previous installation
clean_installation() {
    log_info "Cleaning previous installation..."
    
    # Stop services
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl stop "$WEBGUI_SERVICE" 2>/dev/null || true
    
    # Disable services
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$WEBGUI_SERVICE" 2>/dev/null || true
    
    # Remove services
    rm -f /etc/systemd/system/"$SERVICE_NAME".service
    rm -f /etc/systemd/system/"$WEBGUI_SERVICE".service
    
    # Remove directories
    rm -rf "$INSTALL_DIR"
    rm -rf "$LOG_DIR"
    
    # Remove binary
    rm -f /usr/local/bin/gx-tunnel
    
    systemctl daemon-reload
    log_success "Previous installation cleaned"
}

# Install system dependencies
install_dependencies() {
    log_info "Installing system dependencies..."
    
    # Update package list
    apt-get update -qq
    
    # Install system packages
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
    
    log_success "System dependencies installed"
}

# Install Python packages
install_python_packages() {
    log_info "Installing Python packages..."
    
    # Upgrade pip
    pip3 install --upgrade pip --quiet
    
    # Install required packages
    pip3 install flask flask-cors psutil --quiet
    
    log_success "Python packages installed"
}

# Create directory structure
create_directories() {
    log_info "Creating directory structure..."
    
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$LOG_DIR"
    
    chmod 755 "$INSTALL_DIR"
    chmod 755 "$LOG_DIR"
    
    log_success "Directories created"
}

# Download application files
download_files() {
    log_info "Downloading application files..."
    
    local base_url="https://raw.githubusercontent.com/xcybermanx/GX_tunnel/main"
    
    # Download main application files
    wget -q "$base_url/gx_websocket.py" -O "$INSTALL_DIR/gx_websocket.py"
    wget -q "$base_url/webgui.py" -O "$INSTALL_DIR/webgui.py"
    wget -q "$base_url/gx-tunnel.sh" -O /usr/local/bin/gx-tunnel
    
    chmod +x /usr/local/bin/gx-tunnel
    
    # Create users database
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

    # Create empty statistics database
    touch "$INSTALL_DIR/statistics.db"
    
    log_success "Application files downloaded"
}

# Create systemd services
create_services() {
    log_info "Creating systemd services..."
    
    # Main tunnel service
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

    # Web GUI service
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
    log_success "Systemd services created"
}

# Setup firewall
setup_firewall() {
    log_info "Setting up firewall..."
    
    # Enable UFW
    ufw --force enable > /dev/null 2>&1 || true
    
    # Allow necessary ports
    ufw allow 22/tcp comment 'SSH' > /dev/null 2>&1
    ufw allow 8080/tcp comment 'GX Tunnel' > /dev/null 2>&1
    ufw allow 8081/tcp comment 'GX Web GUI' > /dev/null 2>&1
    ufw allow 80/tcp comment 'HTTP' > /dev/null 2>&1
    ufw allow 443/tcp comment 'HTTPS' > /dev/null 2>&1
    
    log_success "Firewall configured"
}

# Setup fail2ban
setup_fail2ban() {
    log_info "Setting up Fail2Ban..."
    
    # Create basic SSH jail
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
    log_success "Fail2Ban configured"
}

# Verify installation
verify_installation() {
    log_info "Verifying installation..."
    
    local errors=0
    
    # Check files
    [ -f "$INSTALL_DIR/gx_websocket.py" ] || { log_error "Main tunnel script missing"; ((errors++)); }
    [ -f "$INSTALL_DIR/webgui.py" ] || { log_error "Web GUI script missing"; ((errors++)); }
    [ -f "/usr/local/bin/gx-tunnel" ] || { log_error "Management script missing"; ((errors++)); }
    [ -f "/etc/systemd/system/$SERVICE_NAME.service" ] || { log_error "Tunnel service missing"; ((errors++)); }
    [ -f "/etc/systemd/system/$WEBGUI_SERVICE.service" ] || { log_error "Web GUI service missing"; ((errors++)); }
    
    # Check Python packages
    python3 -c "import flask, flask_cors, psutil" > /dev/null 2>&1 || { 
        log_error "Python packages not installed properly"; 
        ((errors++)); 
    }
    
    if [ $errors -eq 0 ]; then
        log_success "Installation verified successfully"
        return 0
    else
        log_error "Installation verification failed with $errors errors"
        return 1
    fi
}

# Start services
start_services() {
    log_info "Starting services..."
    
    systemctl enable "$SERVICE_NAME" "$WEBGUI_SERVICE"
    systemctl start "$SERVICE_NAME" "$WEBGUI_SERVICE"
    
    sleep 3
    
    local tunnel_status=$(systemctl is-active "$SERVICE_NAME")
    local webgui_status=$(systemctl is-active "$WEBGUI_SERVICE")
    
    if [ "$tunnel_status" = "active" ] && [ "$webgui_status" = "active" ]; then
        log_success "Services started successfully"
        return 0
    else
        log_warning "Services partially started (Tunnel: $tunnel_status, WebGUI: $webgui_status)"
        return 1
    fi
}

# Show installation summary
show_summary() {
    local server_ip=$(hostname -I | awk '{print $1}')
    
    echo
    echo -e "${GREEN}"
    echo -e "┌─────────────────────────────────────────────────────────┐"
    echo -e "│                  🎉 INSTALLATION COMPLETE!              │"
    echo -e "└─────────────────────────────────────────────────────────┘"
    echo -e "${NC}"
    echo
    echo -e "${WHITE}📋 Installation Details:${NC}"
    echo -e "  ${CYAN}• Installation: ${GREEN}$INSTALL_DIR${NC}"
    echo -e "  ${CYAN}• Logs: ${GREEN}$LOG_DIR${NC}"
    echo -e "  ${CYAN}• Management: ${GREEN}gx-tunnel${NC}"
    echo
    echo -e "${WHITE}🌐 Access Information:${NC}"
    echo -e "  ${YELLOW}• Tunnel: ${GREEN}ws://$server_ip:8080${NC}"
    echo -e "  ${YELLOW}• Web GUI: ${GREEN}http://$server_ip:8081${NC}"
    echo -e "  ${YELLOW}• Admin Password: ${GREEN}admin123${NC}"
    echo
    echo -e "${WHITE}🚀 Available Commands:${NC}"
    echo -e "  ${GREEN}gx-tunnel menu${NC}       - Show interactive menu"
    echo -e "  ${GREEN}gx-tunnel start${NC}      - Start services"
    echo -e "  ${GREEN}gx-tunnel status${NC}     - Show service status"
    echo -e "  ${GREEN}gx-tunnel add-user${NC}   - Add tunnel user"
    echo -e "  ${GREEN}gx-tunnel list-users${NC} - List all users"
    echo
    echo -e "${WHITE}⏰ Next Steps:${NC}"
    echo -e "  1. ${BLUE}Access Web GUI: http://$server_ip:8081${NC}"
    echo -e "  2. ${BLUE}Add user: gx-tunnel add-user${NC}"
    echo -e "  3. ${BLUE}Check status: gx-tunnel status${NC}"
    echo
}

# Main installation function
main() {
    show_banner
    log_info "Starting GX Tunnel installation..."
    
    # Execute installation steps
    check_root
    clean_installation
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
        show_summary
    else
        log_error "Installation failed verification"
        exit 1
    fi
}

# Run main function
main "$@"
