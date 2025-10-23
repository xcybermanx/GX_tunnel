#!/bin/bash

# GX Tunnel Installation Script
# Created by Jawad - Telegram: @jawadx

# Constants
GX_TUNNEL_SERVICE="gx-tunnel"
GX_WEBGUI_SERVICE="gx-webgui"
INSTALL_DIR="/opt/gx_tunnel"
PYTHON_SCRIPT_PATH="$INSTALL_DIR/gx_websocket.py"
WEBGUI_SCRIPT_PATH="$INSTALL_DIR/webgui.py"
LOG_DIR="/var/log/gx_tunnel"
LOG_FILE="$LOG_DIR/websocket.log"
USER_DB="$INSTALL_DIR/users.json"
STATS_DB="$INSTALL_DIR/statistics.db"

# Color codes for pretty output
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

# Function to show pretty header
show_header() {
    clear
    display_banner
    echo
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[-] This script must be run as root${NC}"
        exit 1
    fi
}

# Function to clean previous installation
clean_previous_installation() {
    echo -e "${YELLOW}[INFO] Cleaning previous installation...${NC}"
    
    # Stop and disable services
    systemctl stop "$GX_TUNNEL_SERVICE" 2>/dev/null
    systemctl stop "$GX_WEBGUI_SERVICE" 2>/dev/null
    systemctl disable "$GX_TUNNEL_SERVICE" 2>/dev/null
    systemctl disable "$GX_WEBGUI_SERVICE" 2>/dev/null
    
    # Remove systemd services
    rm -f /etc/systemd/system/"$GX_TUNNEL_SERVICE".service
    rm -f /etc/systemd/system/"$GX_WEBGUI_SERVICE".service
    
    # Remove installation directory
    rm -rf "$INSTALL_DIR"
    
    # Remove log directory
    rm -rf "$LOG_DIR"
    
    # Remove binary
    rm -f /usr/local/bin/gx-tunnel
    
    systemctl daemon-reload
    echo -e "${GREEN}[SUCCESS] Previous installation cleaned${NC}"
}

# Function to install system dependencies
install_system_dependencies() {
    echo -e "${YELLOW}[INFO] Installing system dependencies...${NC}"
    
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
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[SUCCESS] System dependencies installed${NC}"
    else
        echo -e "${RED}[ERROR] Failed to install system dependencies${NC}"
        exit 1
    fi
}

# Function to install Python packages
install_python_packages() {
    echo -e "${YELLOW}[INFO] Installing Python packages...${NC}"
    
    # Upgrade pip first
    pip3 install --upgrade pip
    
    # Install required Python packages
    pip3 install flask flask-cors psutil
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[SUCCESS] Python packages installed successfully${NC}"
    else
        echo -e "${RED}[ERROR] Failed to install Python packages${NC}"
        exit 1
    fi
}

# Function to create application structure
create_application_structure() {
    echo -e "${YELLOW}[INFO] Creating application structure...${NC}"
    
    # Create installation directory
    mkdir -p "$INSTALL_DIR"
    
    # Create log directory
    mkdir -p "$LOG_DIR"
    
    # Create necessary files
    touch "$LOG_FILE"
    
    # Set proper permissions
    chmod 755 "$INSTALL_DIR"
    chmod 644 "$LOG_FILE"
    
    echo -e "${GREEN}[SUCCESS] Application structure created${NC}"
}

# Function to download application files
download_application_files() {
    echo -e "${YELLOW}[INFO] Downloading application files...${NC}"
    
    # Base URL for raw GitHub content
    local base_url="https://raw.githubusercontent.com/xcybermanx/GX_tunnel/main"
    
    # Download main tunnel script
    if ! wget -q "$base_url/gx_websocket.py" -O "$PYTHON_SCRIPT_PATH"; then
        echo -e "${RED}[ERROR] Failed to download gx_websocket.py${NC}"
        return 1
    fi
    
    # Download web GUI script
    if ! wget -q "$base_url/webgui.py" -O "$WEBGUI_SCRIPT_PATH"; then
        echo -e "${RED}[ERROR] Failed to download webgui.py${NC}"
        return 1
    fi
    
    # Download management script to /usr/local/bin
    if ! wget -q "$base_url/gx-tunnel.sh" -O /usr/local/bin/gx-tunnel; then
        echo -e "${RED}[ERROR] Failed to download management script${NC}"
        return 1
    fi
    
    chmod +x /usr/local/bin/gx-tunnel
    
    # Create initial users database
    cat > "$USER_DB" << EOF
{
    "users": [],
    "settings": {
        "tunnel_port": 8080,
        "webgui_port": 8081,
        "admin_password": "admin123"
    }
}
EOF

    echo -e "${GREEN}[SUCCESS] Application files downloaded${NC}"
    return 0
}

# Function to create systemd services
create_systemd_services() {
    echo -e "${YELLOW}[INFO] Creating systemd services...${NC}"
    
    # Create tunnel service
    cat > /etc/systemd/system/"$GX_TUNNEL_SERVICE".service << EOF
[Unit]
Description=GX Tunnel WebSocket Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/python3 $PYTHON_SCRIPT_PATH
Restart=always
RestartSec=3
StandardOutput=file:$LOG_FILE
StandardError=file:$LOG_FILE

[Install]
WantedBy=multi-user.target
EOF

    # Create web GUI service
    cat > /etc/systemd/system/"$GX_WEBGUI_SERVICE".service << EOF
[Unit]
Description=GX Tunnel Web GUI
After=network.target
Wants=$GX_TUNNEL_SERVICE.service

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/python3 $WEBGUI_SCRIPT_PATH
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd and enable services
    systemctl daemon-reload
    systemctl enable "$GX_TUNNEL_SERVICE"
    systemctl enable "$GX_WEBGUI_SERVICE"
    
    echo -e "${GREEN}[SUCCESS] Systemd services created${NC}"
}

# Function to setup firewall
setup_firewall() {
    echo -e "${YELLOW}[INFO] Setting up firewall...${NC}"
    
    # Enable UFW if not enabled
    if ! ufw status | grep -q "Status: active"; then
        echo "y" | ufw enable
    fi
    
    # Allow SSH
    ufw allow 22/tcp comment 'SSH'
    
    # Allow tunnel port
    ufw allow 8080/tcp comment 'GX Tunnel'
    
    # Allow web GUI port
    ufw allow 8081/tcp comment 'GX Web GUI'
    
    # Allow common web ports
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'
    
    echo -e "${GREEN}[SUCCESS] Firewall configured${NC}"
}

# Function to setup fail2ban
setup_fail2ban() {
    echo -e "${YELLOW}[INFO] Setting up Fail2Ban...${NC}"
    
    # Create fail2ban jail for SSH
    cat > /etc/fail2ban/jail.d/sshd.local << EOF
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
EOF

    # Restart fail2ban
    systemctl restart fail2ban
    
    echo -e "${GREEN}[SUCCESS] Fail2Ban configured${NC}"
}

# Function to verify installation
verify_installation() {
    echo -e "${YELLOW}[INFO] Verifying installation...${NC}"
    
    local errors=0
    
    # Check if files exist
    if [ ! -f "$PYTHON_SCRIPT_PATH" ]; then
        echo -e "${RED}[ERROR] Main tunnel script missing${NC}"
        ((errors++))
    fi
    
    if [ ! -f "$WEBGUI_SCRIPT_PATH" ]; then
        echo -e "${RED}[ERROR] Web GUI script missing${NC}"
        ((errors++))
    fi
    
    if [ ! -f "/usr/local/bin/gx-tunnel" ]; then
        echo -e "${RED}[ERROR] Management script missing${NC}"
        ((errors++))
    fi
    
    # Check if services are installed
    if [ ! -f "/etc/systemd/system/$GX_TUNNEL_SERVICE.service" ]; then
        echo -e "${RED}[ERROR] Tunnel service missing${NC}"
        ((errors++))
    fi
    
    if [ ! -f "/etc/systemd/system/$GX_WEBGUI_SERVICE.service" ]; then
        echo -e "${RED}[ERROR] Web GUI service missing${NC}"
        ((errors++))
    fi
    
    # Check Python packages
    if ! python3 -c "import flask, flask_cors, psutil" &>/dev/null; then
        echo -e "${RED}[ERROR] Python packages not installed properly${NC}"
        ((errors++))
    fi
    
    if [ $errors -eq 0 ]; then
        echo -e "${GREEN}[SUCCESS] Installation verified successfully${NC}"
        return 0
    else
        echo -e "${RED}[ERROR] Installation verification failed with $errors errors${NC}"
        return 1
    fi
}

# Function to start services
start_services() {
    echo -e "${YELLOW}[INFO] Starting services...${NC}"
    
    systemctl start "$GX_TUNNEL_SERVICE"
    systemctl start "$GX_WEBGUI_SERVICE"
    
    sleep 3
    
    # Check if services are running
    local tunnel_status=$(systemctl is-active "$GX_TUNNEL_SERVICE")
    local webgui_status=$(systemctl is-active "$GX_WEBGUI_SERVICE")
    
    if [ "$tunnel_status" = "active" ] && [ "$webgui_status" = "active" ]; then
        echo -e "${GREEN}[SUCCESS] Services started successfully${NC}"
        return 0
    else
        echo -e "${RED}[ERROR] Failed to start services${NC}"
        echo -e "${YELLOW}Tunnel status: $tunnel_status${NC}"
        echo -e "${YELLOW}Web GUI status: $webgui_status${NC}"
        return 1
    fi
}

# Function to show installation summary
show_installation_summary() {
    local server_ip=$(hostname -I | awk '{print $1}')
    
    echo -e "${GREEN}"
    echo -e "┌─────────────────────────────────────────────────────────┐"
    echo -e "│                 🎉 INSTALLATION COMPLETE!               │"
    echo -e "└─────────────────────────────────────────────────────────┘"
    echo -e "${NC}"
    echo -e "${WHITE}📋 Installation Summary:${NC}"
    echo -e "${CYAN}├─ 📁 Installation Directory: $INSTALL_DIR${NC}"
    echo -e "${CYAN}├─ 📝 Log Directory: $LOG_DIR${NC}"
    echo -e "${CYAN}├─ 🔧 Management Command: gx-tunnel${NC}"
    echo -e "${CYAN}├─ 🚀 Tunnel Service: $GX_TUNNEL_SERVICE${NC}"
    echo -e "${CYAN}├─ 🌐 Web GUI Service: $GX_WEBGUI_SERVICE${NC}"
    echo -e "${CYAN}├─ 🔒 Fail2Ban: Enabled${NC}"
    echo -e "${CYAN}└─ 🔥 UFW Firewall: Configured${NC}"
    echo
    echo -e "${WHITE}🌐 Access Information:${NC}"
    echo -e "${YELLOW}├─ Tunnel URL: ws://$server_ip:8080${NC}"
    echo -e "${YELLOW}├─ Web GUI: http://$server_ip:8081${NC}"
    echo -e "${YELLOW}└─ Admin Password: admin123${NC}"
    echo
    echo -e "${WHITE}🚀 Available Commands:${NC}"
    echo -e "${GREEN}├─ gx-tunnel menu       - Show interactive menu${NC}"
    echo -e "${GREEN}├─ gx-tunnel start      - Start services${NC}"
    echo -e "${GREEN}├─ gx-tunnel stop       - Stop services${NC}"
    echo -e "${GREEN}├─ gx-tunnel restart    - Restart services${NC}"
    echo -e "${GREEN}├─ gx-tunnel status     - Show service status${NC}"
    echo -e "${GREEN}├─ gx-tunnel add-user   - Add new tunnel user${NC}"
    echo -e "${GREEN}├─ gx-tunnel list-users - List all users${NC}"
    echo -e "${GREEN}├─ gx-tunnel stats      - Show VPS statistics${NC}"
    echo -e "${GREEN}├─ gx-tunnel logs       - Show real-time logs${NC}"
    echo -e "${GREEN}└─ gx-tunnel fix-deps   - Fix missing dependencies${NC}"
    echo
    echo -e "${WHITE}⏰ Next Steps:${NC}"
    echo -e "${BLUE}1. Access the Web GUI at http://$server_ip:8081${NC}"
    echo -e "${BLUE}2. Use 'gx-tunnel add-user' to create your first user${NC}"
    echo -e "${BLUE}3. Check service status with 'gx-tunnel status'${NC}"
    echo
}

# Main installation function
main_installation() {
    show_header
    echo -e "${GREEN}[GX TUNNEL] Starting installation...${NC}"
    echo
    
    # Execute installation steps
    check_root
    clean_previous_installation
    install_system_dependencies
    install_python_packages
    create_application_structure
    download_application_files
    create_systemd_services
    setup_firewall
    setup_fail2ban
    
    # Verify installation
    if verify_installation; then
        # Start services
        if start_services; then
            show_installation_summary
        else
            echo -e "${YELLOW}[WARNING] Installation completed but services failed to start${NC}"
            echo -e "${YELLOW}You can try starting them manually: systemctl start $GX_TUNNEL_SERVICE $GX_WEBGUI_SERVICE${NC}"
        fi
    else
        echo -e "${RED}[ERROR] Installation failed during verification${NC}"
        exit 1
    fi
}

# Check if script is being sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main_installation
fi
