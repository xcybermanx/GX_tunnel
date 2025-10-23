#!/bin/bash

# GX Tunnel - Complete Installation Script
# Created by Jawad - Telegram: @jawadx

# Constants
INSTALL_DIR="/opt/gx_tunnel"
SYSTEMD_SERVICE_FILE="/etc/systemd/system/gx-tunnel.service"
WEBGUI_SERVICE_FILE="/etc/systemd/system/gx-webgui.service"
PYTHON_BIN=$(command -v python3)
LOG_DIR="/var/log/gx_tunnel"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Function to display banner
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

# Function to print status messages
print_status() {
    echo -e "${BLUE}[*]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[+]${NC} $1"
}

print_error() {
    echo -e "${RED}[-]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Function to install system dependencies
install_dependencies() {
    print_status "Installing system dependencies..."
    
    apt-get update
    apt-get install -y python3 python3-pip dos2unix wget jq net-tools fail2ban sqlite3
    
    # Install Python packages
    pip3 install flask flask-cors psutil
    
    print_success "Dependencies installed successfully"
}

# Function to create directories
create_directories() {
    print_status "Creating installation directories..."
    
    mkdir -p $INSTALL_DIR
    mkdir -p $LOG_DIR
    mkdir -p $INSTALL_DIR/backups
    
    print_success "Directories created successfully"
}

# Function to copy files
copy_files() {
    print_status "Copying application files..."
    
    # Copy the script files to installation directory
    cp gx_websocket.py $INSTALL_DIR/
    cp gx_manager.sh $INSTALL_DIR/
    cp webgui.py $INSTALL_DIR/
    cp config.json $INSTALL_DIR/
    
    # Make scripts executable
    chmod +x $INSTALL_DIR/gx_websocket.py
    chmod +x $INSTALL_DIR/gx_manager.sh
    chmod +x $INSTALL_DIR/webgui.py
    
    # Create symlink for manager script
    ln -sf $INSTALL_DIR/gx_manager.sh /usr/local/bin/gxtunnel
    
    print_success "Files copied successfully"
}

# Function to initialize database
initialize_database() {
    print_status "Initializing database..."
    
    # Create user database
    cat > $INSTALL_DIR/users.json << EOF
{
    "users": [],
    "settings": {
        "max_users": 100,
        "default_expiry_days": 30,
        "max_connections_per_user": 3
    },
    "statistics": {
        "total_connections": 0,
        "total_download": 0,
        "total_upload": 0
    }
}
EOF

    # Initialize SQLite database for statistics
    sqlite3 $INSTALL_DIR/statistics.db << EOF
CREATE TABLE IF NOT EXISTS user_stats (
    username TEXT PRIMARY KEY,
    connections INTEGER DEFAULT 0,
    download_bytes INTEGER DEFAULT 0,
    upload_bytes INTEGER DEFAULT 0,
    last_connection TEXT
);

CREATE TABLE IF NOT EXISTS global_stats (
    key TEXT PRIMARY KEY,
    value INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS connection_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT,
    client_ip TEXT,
    start_time TEXT,
    end_time TEXT,
    duration INTEGER,
    download_bytes INTEGER,
    upload_bytes INTEGER
);
EOF

    print_success "Database initialized successfully"
}

# Function to setup fail2ban
setup_fail2ban() {
    print_status "Setting up Fail2Ban protection..."
    
    # Create fail2ban filter
    cat > /etc/fail2ban/filter.d/gx-tunnel.conf << EOF
[Definition]
failregex = ^.*ERROR.*Authentication failed for .* from <HOST>
            ^.*WARNING.*Wrong password attempt from <HOST>
ignoreregex =
EOF

    # Create fail2ban jail
    cat > /etc/fail2ban/jail.d/gx-tunnel.conf << EOF
[gx-tunnel]
enabled = true
port = 8080,8081
filter = gx-tunnel
logpath = $LOG_DIR/websocket.log
maxretry = 3
bantime = 3600
findtime = 600
EOF

    systemctl enable fail2ban
    systemctl start fail2ban
    
    print_success "Fail2Ban configured successfully"
}

# Function to create systemd services
create_services() {
    print_status "Creating systemd services..."
    
    # Main tunnel service
    cat > $SYSTEMD_SERVICE_FILE << EOF
[Unit]
Description=GX Tunnel WebSocket SSH Service
After=network.target

[Service]
Type=simple
ExecStart=$PYTHON_BIN $INSTALL_DIR/gx_websocket.py
Restart=always
RestartSec=5
User=root
Group=root
WorkingDirectory=$INSTALL_DIR
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

    # Web GUI service
    cat > $WEBGUI_SERVICE_FILE << EOF
[Unit]
Description=GX Tunnel Web GUI
After=network.target gx-tunnel.service

[Service]
Type=simple
ExecStart=$PYTHON_BIN $INSTALL_DIR/webgui.py
Restart=always
RestartSec=5
User=root
Group=root
WorkingDirectory=$INSTALL_DIR
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd
    systemctl daemon-reload
    
    # Enable services
    systemctl enable gx-tunnel gx-webgui
    
    print_success "Systemd services created successfully"
}

# Function to start services
start_services() {
    print_status "Starting GX Tunnel services..."
    
    systemctl start gx-tunnel
    systemctl start gx-webgui
    
    # Wait a moment for services to start
    sleep 3
    
    # Check if services are running
    if systemctl is-active --quiet gx-tunnel && systemctl is-active --quiet gx-webgui; then
        print_success "Services started successfully"
    else
        print_warning "Some services might not have started properly"
    fi
}

# Function to show installation summary
show_summary() {
    local server_ip=$(hostname -I | awk '{print $1}')
    
    echo
    echo -e "${GREEN}╔═══════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           🎯 INSTALLATION COMPLETE            ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${WHITE}┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${WHITE}│ ${CYAN}📍 Installation Details:${NC}                               ${WHITE}│${NC}"
    echo -e "${WHITE}│ ${WHITE}• WebSocket Tunnel: ${GREEN}Port 8080${NC}                         ${WHITE}│${NC}"
    echo -e "${WHITE}│ ${WHITE}• Web GUI: ${GREEN}Port 8081${NC}                                 ${WHITE}│${NC}"
    echo -e "${WHITE}│ ${WHITE}• Installation: ${GREEN}$INSTALL_DIR${NC}                    ${WHITE}│${NC}"
    echo -e "${WHITE}│ ${WHITE}• Logs: ${GREEN}$LOG_DIR${NC}                              ${WHITE}│${NC}"
    echo -e "${WHITE}└─────────────────────────────────────────────────────────┘${NC}"
    echo
    echo -e "${WHITE}┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${WHITE}│ ${CYAN}🚀 Quick Start:${NC}                                         ${WHITE}│${NC}"
    echo -e "${WHITE}│ ${WHITE}1. Access Web GUI: ${GREEN}http://$server_ip:8081${NC}             ${WHITE}│${NC}"
    echo -e "${WHITE}│ ${WHITE}   Username: ${YELLOW}admin${NC} Password: ${YELLOW}admin123${NC}                    ${WHITE}│${NC}"
    echo -e "${WHITE}│ ${WHITE}2. Use CLI Manager: ${GREEN}gxtunnel menu${NC}                     ${WHITE}│${NC}"
    echo -e "${WHITE}│ ${WHITE}3. Add first user: ${GREEN}gxtunnel add-user${NC}                 ${WHITE}│${NC}"
    echo -e "${WHITE}└─────────────────────────────────────────────────────────┘${NC}"
    echo
    echo -e "${WHITE}┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${WHITE}│ ${CYAN}📚 Features:${NC}                                           ${WHITE}│${NC}"
    echo -e "${WHITE}│ ${GREEN}✅ SSH over WebSocket tunneling${NC}                        ${WHITE}│${NC}"
    echo -e "${WHITE}│ ${GREEN}✅ Web-based GUI administration${NC}                        ${WHITE}│${NC}"
    echo -e "${WHITE}│ ${GREEN}✅ User management with expiration${NC}                     ${WHITE}│${NC}"
    echo -e "${WHITE}│ ${GREEN}✅ Fail2Ban protection${NC}                                ${WHITE}│${NC}"
    echo -e "${WHITE}│ ${GREEN}✅ Real-time statistics${NC}                               ${WHITE}│${NC}"
    echo -e "${WHITE}│ ${GREEN}✅ Unlimited bandwidth${NC}                                ${WHITE}│${NC}"
    echo -e "${WHITE}└─────────────────────────────────────────────────────────┘${NC}"
    echo
}

# Main installation function
main() {
    clear
    display_banner
    
    print_status "Starting GX Tunnel installation..."
    
    # Check root privileges
    check_root
    
    # Install dependencies
    install_dependencies
    
    # Create directories
    create_directories
    
    # Copy files
    copy_files
    
    # Initialize database
    initialize_database
    
    # Setup fail2ban
    setup_fail2ban
    
    # Create services
    create_services
    
    # Start services
    start_services
    
    # Show summary
    show_summary
    
    print_success "GX Tunnel installation completed successfully!"
}

# Run main function
main "$@"
