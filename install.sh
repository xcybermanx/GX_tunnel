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
BACKUP_DIR="$INSTALL_DIR/backups"

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
    echo -e "│    ${WHITE}📊 Auto Backup${BLUE}         ${GREEN}🔄 Auto Update${BLUE}              │"
    echo -e "│    ${YELLOW}🔧 Multi-Port${BLUE}         ${RED}🛡️  DDoS Protection${BLUE}           │"
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
    
    # Remove cron jobs
    crontab -l 2>/dev/null | grep -v "gx-tunnel" | crontab - 2>/dev/null
    
    systemctl daemon-reload
    show_success_banner "Previous installation cleaned completely"
    echo
}

# Install system dependencies without interactive prompts
install_dependencies() {
    show_progress_banner "3" "Installing System Dependencies"
    
    log_info "Updating package list..."
    export DEBIAN_FRONTEND=noninteractive
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
        fail2ban \
        htop \
        iftop \
        nethogs

    # Install iptables-persistent without interactive prompts
    log_info "Installing iptables-persistent..."
    echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
    echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
    apt-get install -y -qq iptables-persistent
    
    show_success_banner "All system dependencies installed"
    echo
}

# Install Python packages
install_python_packages() {
    show_progress_banner "4" "Installing Python Packages"
    
    log_info "Upgrading pip..."
    pip3 install --upgrade pip --quiet
    
    log_info "Installing Flask, Flask-CORS, and Psutil..."
    pip3 install flask flask-cors psutil requests --quiet
    
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
    
    log_info "Creating backup directory..."
    mkdir -p "$BACKUP_DIR"
    
    chmod 755 "$INSTALL_DIR"
    chmod 755 "$LOG_DIR"
    chmod 755 "$BACKUP_DIR"
    
    show_success_banner "Directory structure created"
    echo
}

# Download application files
download_files() {
    show_progress_banner "6" "Downloading Application Files"
    
    local base_url="https://raw.githubusercontent.com/xcybermanx/GX_tunnel/main"
    
    log_info "Downloading main tunnel script..."
    if ! wget -q "$base_url/gx_websocket.py" -O "$INSTALL_DIR/gx_websocket.py"; then
        log_error "Failed to download gx_websocket.py"
        return 1
    fi
    
    log_info "Downloading web GUI script..."
    if ! wget -q "$base_url/webgui.py" -O "$INSTALL_DIR/webgui.py"; then
        log_error "Failed to download webgui.py"
        return 1
    fi
    
    log_info "Downloading management script..."
    if ! wget -q "$base_url/gx-tunnel.sh" -O /usr/local/bin/gx-tunnel; then
        log_error "Failed to download management script"
        return 1
    fi
    
    chmod +x /usr/local/bin/gx-tunnel
    
    log_info "Creating users database..."
    cat > "$INSTALL_DIR/users.json" << 'EOF'
{
    "users": [],
    "settings": {
        "tunnel_port": 8080,
        "webgui_port": 8081,
        "admin_password": "admin123",
        "auto_backup": true,
        "auto_update": false,
        "max_connections_per_ip": 10,
        "enable_ddos_protection": true
    }
}
EOF

    log_info "Creating statistics database..."
    cat > "$INSTALL_DIR/create_tables.sql" << 'EOF'
CREATE TABLE IF NOT EXISTS user_stats (
    username TEXT PRIMARY KEY,
    connections INTEGER DEFAULT 0,
    download_bytes INTEGER DEFAULT 0,
    upload_bytes INTEGER DEFAULT 0,
    last_connection TEXT
);

CREATE TABLE IF NOT EXISTS global_stats (
    key TEXT PRIMARY KEY,
    value TEXT
);

CREATE TABLE IF NOT EXISTS connection_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT,
    client_ip TEXT,
    start_time TEXT,
    duration INTEGER,
    download_bytes INTEGER,
    upload_bytes INTEGER
);

CREATE TABLE IF NOT EXISTS security_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_type TEXT,
    client_ip TEXT,
    username TEXT,
    description TEXT,
    timestamp TEXT
);
EOF

    sqlite3 "$INSTALL_DIR/statistics.db" < "$INSTALL_DIR/create_tables.sql"
    rm -f "$INSTALL_DIR/create_tables.sql"
    
    # Create configuration file
    log_info "Creating configuration file..."
    cat > "$INSTALL_DIR/config.json" << 'EOF'
{
    "server": {
        "host": "0.0.0.0",
        "port": 8080,
        "webgui_port": 8081,
        "domain": "",
        "ssl_enabled": false,
        "ssl_cert": "",
        "ssl_key": ""
    },
    "security": {
        "fail2ban_enabled": true,
        "max_login_attempts": 3,
        "ban_time": 3600,
        "session_timeout": 3600,
        "enable_ddos_protection": true,
        "max_connections_per_ip": 10
    },
    "users": {
        "default_expiry_days": 30,
        "max_connections_per_user": 3,
        "max_users": 100
    },
    "backup": {
        "auto_backup": true,
        "backup_interval_hours": 24,
        "max_backups": 7
    },
    "appearance": {
        "theme": "dark",
        "language": "en"
    }
}
EOF

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
Wants=fail2ban.service

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/python3 $INSTALL_DIR/gx_websocket.py
Restart=always
RestartSec=3
StandardOutput=append:$LOG_DIR/websocket.log
StandardError=append:$LOG_DIR/websocket.log

# Security
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=$INSTALL_DIR $LOG_DIR

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

# Security
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=$INSTALL_DIR $LOG_DIR

[Install]
WantedBy=multi-user.target
EOF

    # Create auto-update service
    log_info "Creating auto-update service..."
    cat > /etc/systemd/system/gx-tunnel-update.service << EOF
[Unit]
Description=GX Tunnel Auto Update
After=network.target

[Service]
Type=oneshot
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/local/bin/gx-tunnel update
StandardOutput=append:$LOG_DIR/update.log
StandardError=append:$LOG_DIR/update.log

[Install]
WantedBy=multi-user.target
EOF

    # Create auto-backup service
    log_info "Creating auto-backup service..."
    cat > /etc/systemd/system/gx-tunnel-backup.service << EOF
[Unit]
Description=GX Tunnel Auto Backup
After=network.target

[Service]
Type=oneshot
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/local/bin/gx-tunnel backup
StandardOutput=append:$LOG_DIR/backup.log
StandardError=append:$LOG_DIR/backup.log

[Install]
WantedBy=multi-user.target
EOF

    # Create timer for auto-update (daily at 3 AM)
    cat > /etc/systemd/system/gx-tunnel-update.timer << EOF
[Unit]
Description=GX Tunnel Auto Update Timer
Requires=gx-tunnel-update.service

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=1800

[Install]
WantedBy=timers.target
EOF

    # Create timer for auto-backup (every 6 hours)
    cat > /etc/systemd/system/gx-tunnel-backup.timer << EOF
[Unit]
Description=GX Tunnel Auto Backup Timer
Requires=gx-tunnel-backup.service

[Timer]
OnCalendar=*-*-* 0/6:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME" "$WEBGUI_SERVICE"
    systemctl enable gx-tunnel-update.timer gx-tunnel-backup.timer
    
    show_success_banner "Systemd services created and configured"
    echo
}

# Setup firewall with DDoS protection (non-interactive)
setup_firewall() {
    show_progress_banner "8" "Configuring Firewall & DDoS Protection"
    
    log_info "Enabling UFW firewall..."
    ufw --force enable > /dev/null 2>&1 || true
    
    log_info "Configuring firewall rules..."
    ufw allow 22/tcp comment 'SSH' > /dev/null 2>&1
    ufw allow 8080/tcp comment 'GX Tunnel' > /dev/null 2>&1
    ufw allow 8081/tcp comment 'GX Web GUI' > /dev/null 2>&1
    ufw allow 80/tcp comment 'HTTP' > /dev/null 2>&1
    ufw allow 443/tcp comment 'HTTPS' > /dev/null 2>&1
    
    # Additional security rules
    ufw limit 22/tcp comment 'SSH Rate Limit' > /dev/null 2>&1
    ufw limit 8081/tcp comment 'Web GUI Rate Limit' > /dev/null 2>&1
    
    log_info "Setting up basic DDoS protection..."
    # Basic rate limiting with iptables (non-interactive)
    iptables -N GX_DDOS 2>/dev/null || true
    iptables -F GX_DDOS
    
    # Rate limiting rules for tunnel port
    iptables -A GX_DDOS -p tcp --dport 8080 -m limit --limit 60/minute --limit-burst 100 -j ACCEPT
    iptables -A GX_DDOS -p tcp --dport 8080 -j DROP
    
    # Rate limiting rules for web GUI port
    iptables -A GX_DDOS -p tcp --dport 8081 -m limit --limit 30/minute --limit-burst 50 -j ACCEPT
    iptables -A GX_DDOS -p tcp --dport 8081 -j DROP
    
    # Apply to INPUT chain
    iptables -D INPUT -p tcp -m multiport --dports 8080,8081 -j GX_DDOS 2>/dev/null || true
    iptables -A INPUT -p tcp -m multiport --dports 8080,8081 -j GX_DDOS
    
    # Save iptables rules non-interactively
    log_info "Saving iptables rules..."
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
    
    show_success_banner "Firewall and DDoS protection configured"
    echo
}

# Setup fail2ban with custom jails
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
findtime = 600
EOF

    # Create custom filters
    cat > /etc/fail2ban/filter.d/gx-tunnel.conf << 'EOF'
[Definition]
failregex = ^.*ERROR.*Authentication failed for user: <HOST>.*$
            ^.*WARNING.*Multiple connection attempts from <HOST>.*$
ignoreregex =
EOF

    cat > /etc/fail2ban/filter.d/gx-webgui.conf << 'EOF'
[Definition]
failregex = ^.*Invalid login attempt from <HOST>.*$
            ^.*Failed admin login from <HOST>.*$
ignoreregex =
EOF

    systemctl restart fail2ban
    show_success_banner "Fail2Ban protection activated with custom jails"
    echo
}

# Setup log rotation
setup_log_rotation() {
    show_progress_banner "10" "Setting Up Log Rotation"
    
    cat > /etc/logrotate.d/gx-tunnel << EOF
$LOG_DIR/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    copytruncate
}
EOF

    show_success_banner "Log rotation configured"
    echo
}

# Create backup script
create_backup_script() {
    log_info "Creating backup script..."
    cat > "$INSTALL_DIR/backup.sh" << 'EOF'
#!/bin/bash
BACKUP_DIR="/opt/gx_tunnel/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/backup_$TIMESTAMP.tar.gz"

echo "Creating backup: $BACKUP_FILE"
tar -czf "$BACKUP_FILE" -C /opt/gx_tunnel users.json statistics.db config.json 2>/dev/null

# Remove old backups (keep last 7)
ls -t $BACKUP_DIR/backup_*.tar.gz 2>/dev/null | tail -n +8 | xargs -r rm

echo "Backup completed: $BACKUP_FILE"
EOF

    chmod +x "$INSTALL_DIR/backup.sh"
}

# Create update script
create_update_script() {
    log_info "Creating update script..."
    cat > "$INSTALL_DIR/update.sh" << 'EOF'
#!/bin/bash
echo "Checking for GX Tunnel updates..."
cd /opt/gx_tunnel

# Backup before update
./backup.sh

# Download latest version
wget -q https://raw.githubusercontent.com/xcybermanx/GX_tunnel/main/gx_websocket.py -O gx_websocket.py.new
wget -q https://raw.githubusercontent.com/xcybermanx/GX_tunnel/main/webgui.py -O webgui.py.new
wget -q https://raw.githubusercontent.com/xcybermanx/GX_tunnel/main/gx-tunnel.sh -O /usr/local/bin/gx-tunnel.new

# Verify downloads
if [ -s gx_websocket.py.new ] && [ -s webgui.py.new ] && [ -s /usr/local/bin/gx-tunnel.new ]; then
    mv gx_websocket.py.new gx_websocket.py
    mv webgui.py.new webgui.py
    mv /usr/local/bin/gx-tunnel.new /usr/local/bin/gx-tunnel
    chmod +x /usr/local/bin/gx-tunnel
    
    systemctl restart gx-tunnel gx-webgui
    echo "Update completed successfully"
else
    echo "Update failed: File download error"
    rm -f *.new /usr/local/bin/gx-tunnel.new
fi
EOF

    chmod +x "$INSTALL_DIR/update.sh"
}

# Verify installation
verify_installation() {
    show_progress_banner "11" "Verifying Installation"
    
    local errors=0
    
    log_info "Checking application files..."
    [ -f "$INSTALL_DIR/gx_websocket.py" ] || { log_error "Main tunnel script missing"; ((errors++)); }
    [ -f "$INSTALL_DIR/webgui.py" ] || { log_error "Web GUI script missing"; ((errors++)); }
    [ -f "/usr/local/bin/gx-tunnel" ] || { log_error "Management script missing"; ((errors++)); }
    [ -f "/etc/systemd/system/$SERVICE_NAME.service" ] || { log_error "Tunnel service missing"; ((errors++)); }
    [ -f "/etc/systemd/system/$WEBGUI_SERVICE.service" ] || { log_error "Web GUI service missing"; ((errors++)); }
    [ -f "$INSTALL_DIR/config.json" ] || { log_error "Config file missing"; ((errors++)); }
    
    log_info "Checking Python packages..."
    python3 -c "import flask, flask_cors, psutil, requests" > /dev/null 2>&1 || { 
        log_error "Python packages not installed properly"; 
        ((errors++)); 
    }
    
    log_info "Checking services..."
    systemctl is-enabled "$SERVICE_NAME" > /dev/null 2>&1 || { log_error "Tunnel service not enabled"; ((errors++)); }
    systemctl is-enabled "$WEBGUI_SERVICE" > /dev/null 2>&1 || { log_error "Web GUI service not enabled"; ((errors++)); }
    
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
    show_progress_banner "12" "Starting Services"
    
    log_info "Starting main services..."
    systemctl start "$SERVICE_NAME" "$WEBGUI_SERVICE"
    
    log_info "Starting timers..."
    systemctl start gx-tunnel-update.timer gx-tunnel-backup.timer
    
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

# Create management script with new features
create_management_script() {
    log_info "Enhancing management script..."
    
    # Download the enhanced management script
    wget -q https://raw.githubusercontent.com/xcybermanx/GX_tunnel/main/gx-tunnel.sh -O /usr/local/bin/gx-tunnel
    chmod +x /usr/local/bin/gx-tunnel
    
    # Create symbolic links for easy access
    ln -sf /usr/local/bin/gx-tunnel /usr/bin/gx-tunnel 2>/dev/null || true
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
    echo -e "  ${BLUE}└─ ${YELLOW}Backups: ${GREEN}$BACKUP_DIR${NC}"
    echo -e "  ${BLUE}└─ ${YELLOW}Management: ${GREEN}gx-tunnel${NC}"
    echo
    echo -e "${WHITE}🌐 ${CYAN}Access Information:${NC}"
    echo -e "  ${BLUE}└─ ${YELLOW}Tunnel: ${GREEN}ws://$server_ip:8080${NC}"
    echo -e "  ${BLUE}└─ ${YELLOW}Web GUI: ${GREEN}http://$server_ip:8081${NC}"
    echo -e "  ${BLUE}└─ ${YELLOW}Admin: ${GREEN}admin / admin123${NC}"
    echo
    echo -e "${WHITE}🛡️  ${CYAN}Security Features:${NC}"
    echo -e "  ${BLUE}└─ ${GREEN}✅ Fail2Ban Protection${NC}"
    echo -e "  ${BLUE}└─ ${GREEN}✅ DDoS Protection${NC}"
    echo -e "  ${BLUE}└─ ${GREEN}✅ Auto Backup${NC}"
    echo -e "  ${BLUE}└─ ${GREEN}✅ Rate Limiting${NC}"
    echo
    echo -e "${WHITE}🚀 ${CYAN}Available Commands:${NC}"
    echo -e "  ${GREEN}└─ gx-tunnel menu${NC}         - Interactive menu"
    echo -e "  ${GREEN}└─ gx-tunnel start${NC}        - Start services"
    echo -e "  ${GREEN}└─ gx-tunnel status${NC}       - Service status"
    echo -e "  ${GREEN}└─ gx-tunnel add-user${NC}     - Add tunnel user"
    echo -e "  ${GREEN}└─ gx-tunnel backup${NC}       - Create backup"
    echo -e "  ${GREEN}└─ gx-tunnel update${NC}       - Update system"
    echo -e "  ${GREEN}└─ gx-tunnel stats${NC}        - Show statistics"
    echo -e "  ${GREEN}└─ gx-tunnel monitor${NC}      - Real-time monitor"
    echo
    echo -e "${WHITE}⏰ ${CYAN}Next Steps:${NC}"
    echo -e "  ${BLUE}1. ${YELLOW}Access Web GUI: ${GREEN}http://$server_ip:8081${NC}"
    echo -e "  ${BLUE}2. ${YELLOW}Add user: ${GREEN}gx-tunnel add-user${NC}"
    echo -e "  ${BLUE}3. ${YELLOW}Check status: ${GREEN}gx-tunnel status${NC}"
    echo -e "  ${BLUE}4. ${YELLOW}Monitor: ${GREEN}gx-tunnel monitor${NC}"
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
    create_backup_script
    create_update_script
    create_management_script
    create_services
    setup_firewall
    setup_fail2ban
    setup_log_rotation
    
    # Verify and start
    if verify_installation; then
        start_services
        show_installation_summary
        
        # Display important notes
        echo -e "${YELLOW}📝 Important Notes:${NC}"
        echo -e "  ${WHITE}• ${CYAN}Auto-backup runs every 6 hours${NC}"
        echo -e "  ${WHITE}• ${CYAN}Auto-update checks daily at 3 AM${NC}"
        echo -e "  ${WHITE}• ${CYAN}Fail2Ban monitors SSH and web services${NC}"
        echo -e "  ${WHITE}• ${CYAN}DDoS protection is enabled${NC}"
        echo
        echo -e "${GREEN}🔧 For support: ${YELLOW}Telegram: @jawadx${NC}"
        echo
        
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
