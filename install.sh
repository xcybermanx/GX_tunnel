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
CONFIG_FILE="$INSTALL_DIR/config.json"

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
    echo -e "│    ${CYAN}🌍 Domain Support${BLUE}       ${PURPLE}📱 Mobile App${BLUE}               │"
    echo -e "│    ${GREEN}🔔 Notifications${BLUE}       ${YELLOW}📈 Analytics${BLUE}                │"
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
    rm -f /etc/systemd/system/gx-tunnel-update.service
    rm -f /etc/systemd/system/gx-tunnel-update.timer
    rm -f /etc/systemd/system/gx-tunnel-backup.service
    rm -f /etc/systemd/system/gx-tunnel-backup.timer
    
    log_info "Removing directories..."
    rm -rf "$INSTALL_DIR"
    rm -rf "$LOG_DIR"
    
    log_info "Removing binary..."
    rm -f /usr/local/bin/gx-tunnel
    
    # Remove cron jobs
    crontab -l 2>/dev/null | grep -v "gx-tunnel" | crontab - 2>/dev/null
    
    systemctl daemon-reload
    systemctl reset-failed
    
    show_success_banner "Previous installation cleaned completely"
    echo
}

# Install system dependencies without interactive prompts
install_dependencies() {
    show_progress_banner "3" "Installing System Dependencies"
    
    log_info "Updating package list..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    
    # Pre-configure iptables-persistent to avoid prompts
    log_info "Configuring iptables-persistent for non-interactive installation..."
    echo 'iptables-persistent iptables-persistent/autosave_v4 boolean true' | debconf-set-selections
    echo 'iptables-persistent iptables-persistent/autosave_v6 boolean true' | debconf-set-selections
    
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
        nethogs \
        iptables-persistent \
        git \
        unzip \
        certbot \
        python3-certbot-nginx

    show_success_banner "All system dependencies installed"
    echo
}

# Install Python packages
install_python_packages() {
    show_progress_banner "4" "Installing Python Packages"
    
    log_info "Upgrading pip..."
    pip3 install --upgrade pip --quiet
    
    log_info "Installing Python packages..."
    pip3 install flask flask-cors psutil requests python-socketio eventlet cryptography --quiet
    
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
    
    log_info "Creating SSL directory..."
    mkdir -p "$INSTALL_DIR/ssl"
    
    log_info "Creating themes directory..."
    mkdir -p "$INSTALL_DIR/themes"
    
    chmod 755 "$INSTALL_DIR"
    chmod 755 "$LOG_DIR"
    chmod 755 "$BACKUP_DIR"
    
    show_success_banner "Directory structure created"
    echo
}

# Copy local application files
copy_local_files() {
    show_progress_banner "6" "Copying Application Files"
    
    # Get the directory where this script is located
    local SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    log_info "Copying main tunnel script..."
    if [ -f "$SCRIPT_DIR/gx_websocket.py" ]; then
        cp "$SCRIPT_DIR/gx_websocket.py" "$INSTALL_DIR/gx_websocket.py"
        log_success "Tunnel script copied"
    else
        log_error "gx_websocket.py not found in current directory"
        return 1
    fi
    
    log_info "Copying web GUI script..."
    if [ -f "$SCRIPT_DIR/webgui.py" ]; then
        cp "$SCRIPT_DIR/webgui.py" "$INSTALL_DIR/webgui.py"
        log_success "Web GUI script copied"
    else
        log_error "webgui.py not found in current directory"
        return 1
    fi
    
    log_info "Copying management script..."
    if [ -f "$SCRIPT_DIR/gx_manager.sh" ]; then
        cp "$SCRIPT_DIR/gx_manager.sh" "/usr/local/bin/gx-tunnel"
        chmod +x "/usr/local/bin/gx-tunnel"
        log_success "Management script installed"
    else
        log_error "gx_manager.sh not found in current directory"
        return 1
    fi
    
    log_info "Copying configuration file..."
    if [ -f "$SCRIPT_DIR/config.json" ]; then
        cp "$SCRIPT_DIR/config.json" "$INSTALL_DIR/config.json"
        log_success "Configuration file copied"
    else
        log_warning "config.json not found, creating default..."
        create_default_config
    fi
    
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
        "enable_ddos_protection": true,
        "enable_notifications": true,
        "theme": "dark",
        "language": "en"
    }
}
EOF

    log_info "Creating enhanced statistics database..."
    cat > "$INSTALL_DIR/create_tables.sql" << 'EOF'
CREATE TABLE IF NOT EXISTS user_stats (
    username TEXT PRIMARY KEY,
    connections INTEGER DEFAULT 0,
    download_bytes INTEGER DEFAULT 0,
    upload_bytes INTEGER DEFAULT 0,
    last_connection TEXT,
    total_duration INTEGER DEFAULT 0,
    country TEXT,
    device_type TEXT
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
    upload_bytes INTEGER,
    status TEXT,
    country TEXT,
    user_agent TEXT
);

CREATE TABLE IF NOT EXISTS security_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_type TEXT,
    client_ip TEXT,
    username TEXT,
    description TEXT,
    timestamp TEXT,
    severity TEXT
);

CREATE TABLE IF NOT EXISTS notification_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    type TEXT,
    title TEXT,
    message TEXT,
    timestamp TEXT,
    read_status INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS bandwidth_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT,
    download_bytes INTEGER DEFAULT 0,
    upload_bytes INTEGER DEFAULT 0
);
EOF

    sqlite3 "$INSTALL_DIR/statistics.db" < "$INSTALL_DIR/create_tables.sql"
    rm -f "$INSTALL_DIR/create_tables.sql"
    
    # Create enhanced configuration
    create_enhanced_config
    
    show_success_banner "All application files copied successfully"
    echo
}

# Create enhanced configuration
create_enhanced_config() {
    log_info "Creating enhanced configuration..."
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
        "max_connections_per_ip": 10,
        "allowed_countries": [],
        "blocked_ips": []
    },
    "users": {
        "default_expiry_days": 30,
        "max_connections_per_user": 3,
        "max_users": 100,
        "password_policy": {
            "min_length": 6,
            "require_numbers": true,
            "require_special_chars": false
        }
    },
    "backup": {
        "auto_backup": true,
        "backup_interval_hours": 24,
        "max_backups": 7,
        "backup_to_cloud": false
    },
    "notifications": {
        "enabled": true,
        "email_alerts": false,
        "telegram_alerts": false,
        "discord_alerts": false,
        "alert_on_new_connection": true,
        "alert_on_failed_login": true
    },
    "appearance": {
        "theme": "dark",
        "language": "en",
        "custom_css": "",
        "logo_url": ""
    },
    "advanced": {
        "log_level": "INFO",
        "max_log_size": "10MB",
        "enable_geoip": true,
        "enable_analytics": true,
        "auto_optimize": true,
        "performance_mode": false
    }
}
EOF
}

# Create systemd services
create_services() {
    show_progress_banner "7" "Creating System Services"
    
    log_info "Creating tunnel service..."
    cat > /etc/systemd/system/"$SERVICE_NAME".service << EOF
[Unit]
Description=GX Tunnel WebSocket Service
After=network.target
Wants=network.target

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

# Resource limits
LimitNOFILE=65536
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
EOF

    log_info "Creating web GUI service..."
    cat > /etc/systemd/system/"$WEBGUI_SERVICE".service << EOF
[Unit]
Description=GX Tunnel Web GUI
After=network.target
Wants=network.target

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

# Environment
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

    # Create monitoring service
    log_info "Creating monitoring service..."
    cat > /etc/systemd/system/gx-monitor.service << EOF
[Unit]
Description=GX Tunnel Monitor Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/local/bin/gx-tunnel monitor --daemon
Restart=always
RestartSec=10
StandardOutput=append:$LOG_DIR/monitor.log
StandardError=append:$LOG_DIR/monitor.log

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME" "$WEBGUI_SERVICE" gx-monitor
    
    show_success_banner "Systemd services created and configured"
    echo
}

# Setup firewall with enhanced DDoS protection
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
    
    # Enhanced security rules
    ufw limit 22/tcp comment 'SSH Rate Limit' > /dev/null 2>&1
    ufw limit 8081/tcp comment 'Web GUI Rate Limit' > /dev/null 2>&1
    ufw limit 8080/tcp comment 'Tunnel Rate Limit' > /dev/null 2>&1
    
    log_info "Setting up enhanced DDoS protection..."
    # Enhanced rate limiting with iptables
    iptables -N GX_DDOS 2>/dev/null || true
    iptables -F GX_DDOS
    
    # Enhanced rate limiting rules
    iptables -A GX_DDOS -p tcp --dport 8080 -m connlimit --connlimit-above 50 -j DROP
    iptables -A GX_DDOS -p tcp --dport 8080 -m limit --limit 60/minute --limit-burst 100 -j ACCEPT
    iptables -A GX_DDOS -p tcp --dport 8080 -j DROP
    
    iptables -A GX_DDOS -p tcp --dport 8081 -m connlimit --connlimit-above 20 -j DROP
    iptables -A GX_DDOS -p tcp --dport 8081 -m limit --limit 30/minute --limit-burst 50 -j ACCEPT
    iptables -A GX_DDOS -p tcp --dport 8081 -j DROP
    
    # SYN flood protection
    iptables -A GX_DDOS -p tcp --syn -m limit --limit 1/s --limit-burst 3 -j ACCEPT
    iptables -A GX_DDOS -p tcp --syn -j DROP
    
    # Apply to INPUT chain
    iptables -D INPUT -p tcp -m multiport --dports 8080,8081 -j GX_DDOS 2>/dev/null || true
    iptables -A INPUT -p tcp -m multiport --dports 8080,8081 -j GX_DDOS
    
    # Save iptables rules
    log_info "Saving iptables rules..."
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
    
    show_success_banner "Enhanced firewall and DDoS protection configured"
    echo
}

# Setup enhanced fail2ban with custom jails
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
ignoreip = 127.0.0.1/8
EOF

    log_info "Configuring GX Tunnel protection..."
    cat > /etc/fail2ban/jail.d/gx-tunnel.local << EOF
[gx-tunnel]
enabled = true
port = 8080,8081
filter = gx-tunnel
logpath = $LOG_DIR/websocket.log
maxretry = 5
bantime = 3600
findtime = 600
ignoreip = 127.0.0.1/8

[gx-webgui]
enabled = true
port = 8081
filter = gx-webgui
logpath = $LOG_DIR/webgui.log
maxretry = 3
bantime = 7200
findtime = 600
ignoreip = 127.0.0.1/8

[gx-ddos]
enabled = true
port = 8080,8081
filter = gx-ddos
logpath = $LOG_DIR/websocket.log
maxretry = 10
bantime = 86400
findtime = 300
ignoreip = 127.0.0.1/8
EOF

    # Create enhanced filters
    cat > /etc/fail2ban/filter.d/gx-tunnel.conf << 'EOF'
[Definition]
failregex = ^.*ERROR.*Authentication failed for user: <HOST>.*$
            ^.*WARNING.*Multiple connection attempts from <HOST>.*$
            ^.*ERROR.*Invalid credentials from <HOST>.*$
ignoreregex =
EOF

    cat > /etc/fail2ban/filter.d/gx-webgui.conf << 'EOF'
[Definition]
failregex = ^.*Invalid login attempt from <HOST>.*$
            ^.*Failed admin login from <HOST>.*$
            ^.*ERROR.*Login failed for user .* from <HOST>.*$
ignoreregex =
EOF

    cat > /etc/fail2ban/filter.d/gx-ddos.conf << 'EOF'
[Definition]
failregex = ^.*WARNING.*Multiple rapid connections from <HOST>.*$
            ^.*ERROR.*Connection limit exceeded from <HOST>.*$
            ^.*WARNING.*Possible DDoS attack from <HOST>.*$
ignoreregex =
EOF

    systemctl restart fail2ban
    show_success_banner "Enhanced Fail2Ban protection activated"
    echo
}

# Setup log rotation
setup_log_rotation() {
    show_progress_banner "10" "Setting Up Log Rotation"
    
    cat > /etc/logrotate.d/gx-tunnel << EOF
$LOG_DIR/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    copytruncate
    maxsize 100M
}
EOF

    show_success_banner "Enhanced log rotation configured"
    echo
}

# Create enhanced backup script
create_backup_script() {
    log_info "Creating enhanced backup script..."
    cat > "$INSTALL_DIR/backup.sh" << 'EOF'
#!/bin/bash

# GX Tunnel Backup Script
# Created by Jawad - Telegram: @jawadx

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

BACKUP_DIR="/opt/gx_tunnel/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/backup_$TIMESTAMP.tar.gz"
LOG_FILE="/var/log/gx_tunnel/backup.log"

# Log function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

echo "🔧 Starting GX Tunnel Backup..."
log "Starting backup process"

# Create backup
echo "📦 Creating backup archive..."
tar -czf "$BACKUP_FILE" \
    -C /opt/gx_tunnel \
    users.json \
    statistics.db \
    config.json \
    ssl/ \
    themes/ 2>/dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Backup created: $BACKUP_FILE${NC}"
    log "Backup created successfully: $BACKUP_FILE"
    
    # Backup size
    BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    echo "💾 Backup size: $BACKUP_SIZE"
    log "Backup size: $BACKUP_SIZE"
    
    # Remove old backups (keep last 10)
    OLD_BACKUPS=$(ls -t $BACKUP_DIR/backup_*.tar.gz 2>/dev/null | tail -n +11)
    if [ -n "$OLD_BACKUPS" ]; then
        echo "🗑️  Cleaning old backups..."
        echo "$OLD_BACKUPS" | xargs -r rm
        log "Removed old backups"
    fi
    
    # List current backups
    CURRENT_BACKUPS=$(ls -1 $BACKUP_DIR/backup_*.tar.gz 2>/dev/null | wc -l)
    echo "📊 Total backups: $CURRENT_BACKUPS"
    log "Total backups: $CURRENT_BACKUPS"
    
    echo -e "${GREEN}🎉 Backup completed successfully!${NC}"
else
    echo -e "${RED}❌ Backup creation failed${NC}"
    log "Backup creation failed"
    exit 1
fi
EOF

    chmod +x "$INSTALL_DIR/backup.sh"
}

# Create enhanced update script
create_update_script() {
    log_info "Creating enhanced update script..."
    cat > "$INSTALL_DIR/update.sh" << 'EOF'
#!/bin/bash

# GX Tunnel Update Script
# Created by Jawad - Telegram: @jawadx

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INSTALL_DIR="/opt/gx_tunnel"
LOG_FILE="/var/log/gx_tunnel/update.log"
BACKUP_SCRIPT="$INSTALL_DIR/backup.sh"

# Log function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

echo "🔄 Starting GX Tunnel Update..."
log "Starting update process"

# Backup before update
echo "💾 Creating backup before update..."
if [ -f "$BACKUP_SCRIPT" ]; then
    bash "$BACKUP_SCRIPT"
else
    echo -e "${YELLOW}⚠️  Backup script not found, skipping backup${NC}"
    log "Backup script not found, skipping backup"
fi

# Get the latest version from GitHub
echo "📥 Downloading updates..."
cd "$INSTALL_DIR"

# Download latest files with retry logic
download_file() {
    local url=$1
    local output=$2
    local retries=3
    local count=0
    
    while [ $count -lt $retries ]; do
        if wget -q "$url" -O "$output"; then
            return 0
        fi
        count=$((count + 1))
        echo "Retrying download... ($count/$retries)"
        sleep 2
    done
    return 1
}

# Download updated files
if download_file "https://raw.githubusercontent.com/xcybermanx/GX_tunnel/main/gx_websocket.py" "gx_websocket.py.new" &&
   download_file "https://raw.githubusercontent.com/xcybermanx/GX_tunnel/main/webgui.py" "webgui.py.new" &&
   download_file "https://raw.githubusercontent.com/xcybermanx/GX_tunnel/main/gx_manager.sh" "/usr/local/bin/gx-tunnel.new"; then

    # Verify downloads
    if [ -s "gx_websocket.py.new" ] && [ -s "webgui.py.new" ] && [ -s "/usr/local/bin/gx-tunnel.new" ]; then
        echo "✅ Files downloaded successfully"
        log "Update files downloaded successfully"
        
        # Replace old files
        mv "gx_websocket.py.new" "gx_websocket.py"
        mv "webgui.py.new" "webgui.py"
        mv "/usr/local/bin/gx-tunnel.new" "/usr/local/bin/gx-tunnel"
        chmod +x "/usr/local/bin/gx-tunnel"
        
        # Restart services
        echo "🔧 Restarting services..."
        systemctl restart gx-tunnel gx-webgui gx-monitor
        
        # Wait for services to start
        sleep 5
        
        # Check service status
        if systemctl is-active --quiet gx-tunnel && systemctl is-active --quiet gx-webgui; then
            echo -e "${GREEN}🎉 Update completed successfully!${NC}"
            log "Update completed successfully"
            
            # Show version information
            echo ""
            echo "📊 Update Summary:"
            echo "  ✅ Services restarted"
            echo "  ✅ Files updated"
            echo "  ✅ Backup created"
            echo ""
            echo "🌐 Web GUI: http://$(hostname -I | awk '{print $1}'):8081"
            
        else
            echo -e "${RED}❌ Services failed to start after update${NC}"
            log "Services failed to start after update"
        fi
        
    else
        echo -e "${RED}❌ Downloaded files are empty or corrupted${NC}"
        log "Downloaded files are empty or corrupted"
        # Clean up failed downloads
        rm -f *.new /usr/local/bin/gx-tunnel.new
    fi
else
    echo -e "${RED}❌ Update failed: Could not download new files${NC}"
    log "Update failed: Could not download new files"
    # Clean up failed downloads
    rm -f *.new /usr/local/bin/gx-tunnel.new
fi
EOF

    chmod +x "$INSTALL_DIR/update.sh"
}

# Create monitoring and analytics script
create_monitoring_script() {
    log_info "Creating monitoring script..."
    cat > "$INSTALL_DIR/monitor.py" << 'EOF'
#!/usr/bin/python3
import time
import json
import sqlite3
import psutil
import subprocess
from datetime import datetime, timedelta
import logging

# Configuration
INSTALL_DIR = "/opt/gx_tunnel"
STATS_DB = f"{INSTALL_DIR}/statistics.db"
LOG_FILE = "/var/log/gx_tunnel/monitor.log"

# Setup logging
logging.basicConfig(
    filename=LOG_FILE,
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

class SystemMonitor:
    def __init__(self):
        self.conn = sqlite3.connect(STATS_DB)
        self.setup_database()
    
    def setup_database(self):
        cursor = self.conn.cursor()
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS system_stats (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT,
                cpu_percent REAL,
                memory_percent REAL,
                disk_percent REAL,
                network_sent INTEGER,
                network_recv INTEGER,
                active_connections INTEGER
            )
        ''')
        self.conn.commit()
    
    def collect_system_stats(self):
        try:
            # CPU usage
            cpu_percent = psutil.cpu_percent(interval=1)
            
            # Memory usage
            memory = psutil.virtual_memory()
            memory_percent = memory.percent
            
            # Disk usage
            disk = psutil.disk_usage('/')
            disk_percent = disk.percent
            
            # Network usage
            net_io = psutil.net_io_counters()
            network_sent = net_io.bytes_sent
            network_recv = net_io.bytes_recv
            
            # Active connections (estimate)
            try:
                result = subprocess.run(['ss', '-tun'], capture_output=True, text=True)
                active_connections = len(result.stdout.strip().split('\n')) - 1
            except:
                active_connections = 0
            
            return {
                'timestamp': datetime.now().isoformat(),
                'cpu_percent': cpu_percent,
                'memory_percent': memory_percent,
                'disk_percent': disk_percent,
                'network_sent': network_sent,
                'network_recv': network_recv,
                'active_connections': active_connections
            }
        except Exception as e:
            logging.error(f"Error collecting system stats: {e}")
            return None
    
    def save_stats(self, stats):
        if stats:
            cursor = self.conn.cursor()
            cursor.execute('''
                INSERT INTO system_stats 
                (timestamp, cpu_percent, memory_percent, disk_percent, network_sent, network_recv, active_connections)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            ''', (
                stats['timestamp'],
                stats['cpu_percent'],
                stats['memory_percent'],
                stats['disk_percent'],
                stats['network_sent'],
                stats['network_recv'],
                stats['active_connections']
            ))
            self.conn.commit()
    
    def cleanup_old_stats(self):
        """Remove stats older than 30 days"""
        try:
            cursor = self.conn.cursor()
            thirty_days_ago = (datetime.now() - timedelta(days=30)).isoformat()
            cursor.execute('DELETE FROM system_stats WHERE timestamp < ?', (thirty_days_ago,))
            self.conn.commit()
            deleted_count = cursor.rowcount
            if deleted_count > 0:
                logging.info(f"Cleaned up {deleted_count} old system stats records")
        except Exception as e:
            logging.error(f"Error cleaning up old stats: {e}")
    
    def run(self):
        logging.info("Starting system monitor")
        try:
            while True:
                stats = self.collect_system_stats()
                if stats:
                    self.save_stats(stats)
                    logging.info(f"System stats collected: CPU {stats['cpu_percent']}%, Memory {stats['memory_percent']}%")
                
                # Cleanup every hour
                if datetime.now().minute == 0:
                    self.cleanup_old_stats()
                
                time.sleep(60)  # Collect every minute
                
        except KeyboardInterrupt:
            logging.info("System monitor stopped by user")
        except Exception as e:
            logging.error(f"System monitor error: {e}")
        finally:
            self.conn.close()

if __name__ == "__main__":
    monitor = SystemMonitor()
    monitor.run()
EOF

    chmod +x "$INSTALL_DIR/monitor.py"
}

# Create enhanced management script
create_enhanced_management_script() {
    log_info "Creating enhanced management script..."
    
    # Download or create enhanced management script
    cat > /usr/local/bin/gx-tunnel << 'EOF'
#!/bin/bash

# GX Tunnel Enhanced Management Script
# Created by Jawad - Telegram: @jawadx

# Constants
GX_TUNNEL_SERVICE="gx-tunnel"
GX_WEBGUI_SERVICE="gx-webgui"
GX_MONITOR_SERVICE="gx-monitor"
INSTALL_DIR="/opt/gx_tunnel"
LOG_DIR="/var/log/gx_tunnel"
USER_DB="$INSTALL_DIR/users.json"
STATS_DB="$INSTALL_DIR/statistics.db"
CONFIG_FILE="$INSTALL_DIR/config.json"

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
   echo -e "│    ${WHITE}📊 Auto Backup${BLUE}         ${GREEN}🔄 Auto Update${BLUE}              │"
   echo -e "│    ${YELLOW}🔧 Multi-Port${BLUE}         ${RED}🛡️  DDoS Protection${BLUE}           │"
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

# Function to get server IP
get_server_ip() {
    local ipv4=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -1)
    if [ -n "$ipv4" ]; then
        echo "$ipv4"
    else
        echo "unknown"
    fi
}

# Enhanced user management functions
load_user_db() {
    if [ -f "$USER_DB" ]; then
        cat "$USER_DB"
    else
        echo '{"users": [], "settings": {}}'
    fi
}

save_user_db() {
    local data="$1"
    echo "$data" > "$USER_DB"
    chmod 600 "$USER_DB"
}

# Enhanced add user function
add_tunnel_user() {
    echo -e "${WHITE}👤 CREATE SSH TUNNEL USER${NC}"
    echo -e "${CYAN}───────────────────────────────────────────────────────────${NC}"
    
    read -p "Enter username: " username
    
    # Validate username
    if [[ ! "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        echo -e "${RED}❌ Username can only contain lowercase letters, numbers, hyphens, and underscores${NC}"
        return 1
    fi
    
    read -p "Enter password: " -s password
    echo
    echo

    if [ -z "$username" ] || [ -z "$password" ]; then
        echo -e "${RED}❌ Username or password cannot be empty${NC}"
        return 1
    fi

    # Check if user exists in database
    local user_db=$(load_user_db)
    local user_exists=$(echo "$user_db" | jq -r ".users[] | select(.username == \"$username\") | .username")
    
    if [ -n "$user_exists" ]; then
        echo -e "${RED}❌ User $username already exists${NC}"
        return 1
    fi

    # Ask for expiration date
    echo -e "${YELLOW}Set account expiration (leave empty for no expiration):${NC}"
    read -p "Enter expiration date (YYYY-MM-DD): " expiry_date

    # Validate date format if provided
    if [ -n "$expiry_date" ]; then
        if ! date -d "$expiry_date" >/dev/null 2>&1; then
            echo -e "${RED}❌ Invalid date format. Use YYYY-MM-DD${NC}"
            return 1
        fi
    fi

    # Ask for maximum connections
    read -p "Enter maximum simultaneous connections (default: 3): " max_connections
    max_connections=${max_connections:-3}

    # Add to user database only (no system user creation)
    local new_user=$(jq -n \
        --arg username "$username" \
        --arg password "$password" \
        --arg created "$(date +%Y-%m-%d)" \
        --arg expires "$expiry_date" \
        --argjson max_conn "$max_connections" \
        '{username: $username, password: $password, created: $created, expires: $expires, max_connections: $max_conn, active: true}')
    
    local updated_db=$(echo "$user_db" | jq ".users += [$new_user]")
    save_user_db "$updated_db"
    
    echo -e "${GREEN}✅ User $username created successfully${NC}"
    show_user_config "$username" "$password" "$expiry_date" "$max_connections"
}

# Enhanced user configuration display
show_user_config() {
    local username="$1"
    local password="$2"
    local expiry_date="$3"
    local max_connections="$4"
    local server_ip=$(get_server_ip)
    
    echo
    echo -e "${WHITE}🔧 USER CONFIGURATION${NC}"
    echo -e "${CYAN}┌───────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│ ${GREEN}📋 Connection Details:${NC}                               ${CYAN}│${NC}"
    echo -e "${CYAN}│ ${WHITE}Server: ${YELLOW}$server_ip${NC}                                       ${CYAN}│${NC}"
    echo -e "${CYAN}│ ${WHITE}Port: ${YELLOW}8080${NC}                                           ${CYAN}│${NC}"
    echo -e "${CYAN}│ ${WHITE}Username: ${YELLOW}$username${NC}                                     ${CYAN}│${NC}"
    echo -e "${CYAN}│ ${WHITE}Password: ${YELLOW}$password${NC}                                     ${CYAN}│${NC}"
    if [ -n "$expiry_date" ]; then
        echo -e "${CYAN}│ ${WHITE}Expires: ${YELLOW}$expiry_date${NC}                                   ${CYAN}│${NC}"
    else
        echo -e "${CYAN}│ ${WHITE}Expires: ${GREEN}Never${NC}                                       ${CYAN}│${NC}"
    fi
    echo -e "${CYAN}│ ${WHITE}Max Connections: ${YELLOW}$max_connections${NC}                            ${CYAN}│${NC}"
    echo -e "${CYAN}└───────────────────────────────────────────────────────────┘${NC}"
    echo
    echo -e "${WHITE}📱 Required Headers:${NC}"
    echo -e "${CYAN}┌───────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│ ${YELLOW}X-Username: $username${NC}                                   ${CYAN}│${NC}"
    echo -e "${CYAN}│ ${YELLOW}X-Password: $password${NC}                                   ${CYAN}│${NC}"
    echo -e "${CYAN}│ ${YELLOW}X-Real-Host: target.com:22${NC}                              ${CYAN}│${NC}"
    echo -e "${CYAN}└───────────────────────────────────────────────────────────┘${NC}"
    echo
    echo -e "${WHITE}🌐 Web GUI:${NC}"
    echo -e "${CYAN}┌───────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│ ${GREEN}http://$server_ip:8081${NC}                                  ${CYAN}│${NC}"
    echo -e "${CYAN}│ ${YELLOW}Admin Password: admin123${NC}                                ${CYAN}│${NC}"
    echo -e "${CYAN}└───────────────────────────────────────────────────────────┘${NC}"
}

# Enhanced service status
show_service_status() {
    echo -e "${WHITE}📊 SERVICE STATUS${NC}"
    echo -e "${CYAN}───────────────────────────────────────────────────────────${NC}"
    
    local server_ip=$(get_server_ip)
    local tunnel_status=$(systemctl is-active "$GX_TUNNEL_SERVICE")
    local webgui_status=$(systemctl is-active "$GX_WEBGUI_SERVICE")
    local monitor_status=$(systemctl is-active "$GX_MONITOR_SERVICE")
    
    echo -e "${WHITE}┌─────────────────────────────────────────────────────────┐${NC}"
    
    if [ "$tunnel_status" = "active" ]; then
        echo -e "${WHITE}│ ${GREEN}🟢 Tunnel Service: ${GREEN}ACTIVE${WHITE}                            │${NC}"
    else
        echo -e "${WHITE}│ ${RED}🔴 Tunnel Service: ${RED}INACTIVE${WHITE}                          │${NC}"
    fi
    
    if [ "$webgui_status" = "active" ]; then
        echo -e "${WHITE}│ ${GREEN}🟢 Web GUI: ${GREEN}ACTIVE${WHITE}                                 │${NC}"
    else
        echo -e "${WHITE}│ ${RED}🔴 Web GUI: ${RED}INACTIVE${WHITE}                               │${NC}"
    fi
    
    if [ "$monitor_status" = "active" ]; then
        echo -e "${WHITE}│ ${GREEN}🟢 Monitor: ${GREEN}ACTIVE${WHITE}                                │${NC}"
    else
        echo -e "${WHITE}│ ${YELLOW}🟡 Monitor: ${YELLOW}INACTIVE${WHITE}                             │${NC}"
    fi
    
    echo -e "${WHITE}│ ${CYAN}📍 Server IP: ${YELLOW}$server_ip${WHITE}                         │${NC}"
    echo -e "${WHITE}│ ${CYAN}🌐 Tunnel Port: ${YELLOW}8080${WHITE}                               │${NC}"
    echo -e "${WHITE}│ ${CYAN}🖥️  Web GUI Port: ${YELLOW}8081${WHITE}                              │${NC}"
    echo -e "${WHITE}└─────────────────────────────────────────────────────────┘${NC}"
}

# Enhanced statistics
show_enhanced_stats() {
    echo -e "${WHITE}📈 ENHANCED STATISTICS${NC}"
    echo -e "${CYAN}───────────────────────────────────────────────────────────${NC}"
    
    if [ -f "$STATS_DB" ]; then
        # Get total users
        local user_db=$(load_user_db)
        local total_users=$(echo "$user_db" | jq '.users | length')
        
        # Get connection stats from database
        local total_connections=$(sqlite3 "$STATS_DB" "SELECT COUNT(*) FROM connection_log;" 2>/dev/null || echo "0")
        local total_download=$(sqlite3 "$STATS_DB" "SELECT SUM(download_bytes) FROM connection_log;" 2>/dev/null || echo "0")
        local total_upload=$(sqlite3 "$STATS_DB" "SELECT SUM(upload_bytes) FROM connection_log;" 2>/dev/null || echo "0")
        
        # Convert bytes to human readable
        download_human=$(numfmt --to=iec --suffix=B "$total_download" 2>/dev/null || echo "0B")
        upload_human=$(numfmt --to=iec --suffix=B "$total_upload" 2>/dev/null || echo "0B")
        
        echo -e "${WHITE}┌─────────────────────────────────────────────────────────┐${NC}"
        echo -e "${WHITE}│ ${CYAN}👥 Total Users: ${YELLOW}$total_users${WHITE}                                   │${NC}"
        echo -e "${WHITE}│ ${CYAN}🔗 Total Connections: ${YELLOW}$total_connections${WHITE}                           │${NC}"
        echo -e "${WHITE}│ ${CYAN}📥 Total Download: ${YELLOW}$download_human${WHITE}                           │${NC}"
        echo -e "${WHITE}│ ${CYAN}📤 Total Upload: ${YELLOW}$upload_human${WHITE}                             │${NC}"
        echo -e "${WHITE}└─────────────────────────────────────────────────────────┘${NC}"
        
        # Show recent connections
        echo
        echo -e "${YELLOW}🕒 Recent Connections:${NC}"
        sqlite3 -header -column "$STATS_DB" "SELECT username, client_ip, duration, download_bytes, upload_bytes FROM connection_log ORDER BY id DESC LIMIT 5;" 2>/dev/null || echo "No connection data available"
    else
        echo -e "${RED}Statistics database not found${NC}"
    fi
}

# Backup function
backup_system() {
    echo -e "${WHITE}💾 BACKUP SYSTEM${NC}"
    echo -e "${CYAN}───────────────────────────────────────────────────────────${NC}"
    
    if [ -f "$INSTALL_DIR/backup.sh" ]; then
        bash "$INSTALL_DIR/backup.sh"
    else
        echo -e "${RED}Backup script not found${NC}"
    fi
}

# Update function
update_system() {
    echo -e "${WHITE}🔄 UPDATE SYSTEM${NC}"
    echo -e "${CYAN}───────────────────────────────────────────────────────────${NC}"
    
    if [ -f "$INSTALL_DIR/update.sh" ]; then
        bash "$INSTALL_DIR/update.sh"
    else
        echo -e "${RED}Update script not found${NC}"
    fi
}

# Monitor function
show_monitor() {
    echo -e "${WHITE}📊 REAL-TIME MONITOR${NC}"
    echo -e "${CYAN}───────────────────────────────────────────────────────────${NC}"
    echo -e "${YELLOW}Press Ctrl+C to stop monitoring${NC}"
    echo
    
    while true; do
        clear
        show_header
        show_service_status
        echo
        show_enhanced_stats
        echo
        echo -e "${CYAN}Refreshing every 5 seconds...${NC}"
        sleep 5
    done
}

# Enhanced main menu
show_main_menu() {
    while true; do
        show_header
        
        echo -e "${WHITE}🏠 ENHANCED MAIN MENU${NC}"
        echo -e "${CYAN}───────────────────────────────────────────────────────────${NC}"
        echo -e "${WHITE}1) ${GREEN}👤 User Management${NC}"
        echo -e "${WHITE}2) ${YELLOW}🚀 Service Control${NC}"
        echo -e "${WHITE}3) ${BLUE}📊 Service Status${NC}"
        echo -e "${WHITE}4) ${PURPLE}💻 System Statistics${NC}"
        echo -e "${WHITE}5) ${CYAN}📋 View Users${NC}"
        echo -e "${WHITE}6) ${WHITE}📜 Real-time Logs${NC}"
        echo -e "${WHITE}7) ${GREEN}📈 Enhanced Stats${NC}"
        echo -e "${WHITE}8) ${YELLOW}🔍 Real-time Monitor${NC}"
        echo -e "${WHITE}9) ${BLUE}💾 Backup System${NC}"
        echo -e "${WHITE}10) ${PURPLE}🔄 Update System${NC}"
        echo -e "${WHITE}0) ${RED}❌ Exit${NC}"
        echo -e "${CYAN}───────────────────────────────────────────────────────────${NC}"
        
        read -p "Enter your choice [0-10]: " choice
        
        case $choice in
            1) show_user_management_menu ;;
            2) show_service_control_menu ;;
            3) show_service_status; read -p "Press Enter to continue..." ;;
            4) show_system_stats; read -p "Press Enter to continue..." ;;
            5) list_tunnel_users; read -p "Press Enter to continue..." ;;
            6) show_realtime_logs ;;
            7) show_enhanced_stats; read -p "Press Enter to continue..." ;;
            8) show_monitor ;;
            9) backup_system; read -p "Press Enter to continue..." ;;
            10) update_system; read -p "Press Enter to continue..." ;;
            0) echo -e "${GREEN}👋 Thank you for using GX Tunnel!${NC}"; exit 0 ;;
            *) echo -e "${RED}❌ Invalid choice. Please try again.${NC}"; sleep 2 ;;
        esac
    done
}

# Enhanced user management menu
show_user_management_menu() {
    while true; do
        show_header
        
        echo -e "${WHITE}👤 ENHANCED USER MANAGEMENT${NC}"
        echo -e "${CYAN}───────────────────────────────────────────────────────────${NC}"
        echo -e "${WHITE}1) ${GREEN}➕ Add User${NC}"
        echo -e "${WHITE}2) ${RED}🗑️  Delete User${NC}"
        echo -e "${WHITE}3) ${BLUE}📋 List Users${NC}"
        echo -e "${WHITE}4) ${YELLOW}📊 User Statistics${NC}"
        echo -e "${WHITE}5) ${PURPLE}🔙 Back to Main Menu${NC}"
        echo -e "${CYAN}───────────────────────────────────────────────────────────${NC}"
        
        read -p "Enter your choice [1-5]: " choice
        
        case $choice in
            1) add_tunnel_user; read -p "Press Enter to continue..." ;;
            2) delete_tunnel_user; read -p "Press Enter to continue..." ;;
            3) list_tunnel_users; read -p "Press Enter to continue..." ;;
            4) show_user_statistics; read -p "Press Enter to continue..." ;;
            5) break ;;
            *) echo -e "${RED}❌ Invalid choice. Please try again.${NC}"; sleep 2 ;;
        esac
    done
}

# Service control menu
show_service_control_menu() {
    while true; do
        show_header
        
        echo -e "${WHITE}🚀 SERVICE CONTROL${NC}"
        echo -e "${CYAN}───────────────────────────────────────────────────────────${NC}"
        echo -e "${WHITE}1) ${GREEN}▶️  Start Services${NC}"
        echo -e "${WHITE}2) ${RED}⏹️  Stop Services${NC}"
        echo -e "${WHITE}3) ${YELLOW}🔄 Restart Services${NC}"
        echo -e "${WHITE}4) ${BLUE}📊 Service Status${NC}"
        echo -e "${WHITE}5) ${PURPLE}🔙 Back to Main Menu${NC}"
        echo -e "${CYAN}───────────────────────────────────────────────────────────${NC}"
        
        read -p "Enter your choice [1-5]: " choice
        
        case $choice in
            1) start_services; read -p "Press Enter to continue..." ;;
            2) stop_services; read -p "Press Enter to continue..." ;;
            3) restart_services; read -p "Press Enter to continue..." ;;
            4) show_service_status; read -p "Press Enter to continue..." ;;
            5) break ;;
            *) echo -e "${RED}❌ Invalid choice. Please try again.${NC}"; sleep 2 ;;
        esac
    done
}

# Include other functions from the original script...
# [Previous functions like start_services, stop_services, list_tunnel_users, etc.]

# Service control functions
start_services() {
    echo -e "${WHITE}🚀 STARTING GX TUNNEL SERVICES${NC}"
    echo -e "${CYAN}───────────────────────────────────────────────────────────${NC}"
    
    systemctl start "$GX_TUNNEL_SERVICE"
    systemctl start "$GX_WEBGUI_SERVICE"
    systemctl start "$GX_MONITOR_SERVICE"
    sleep 2
    show_service_status
}

stop_services() {
    echo -e "${WHITE}🛑 STOPPING GX TUNNEL SERVICES${NC}"
    echo -e "${CYAN}───────────────────────────────────────────────────────────${NC}"
    
    systemctl stop "$GX_TUNNEL_SERVICE"
    systemctl stop "$GX_WEBGUI_SERVICE"
    systemctl stop "$GX_MONITOR_SERVICE"
    sleep 2
    show_service_status
}

restart_services() {
    echo -e "${WHITE}🔄 RESTARTING GX TUNNEL SERVICES${NC}"
    echo -e "${CYAN}───────────────────────────────────────────────────────────${NC}"
    
    systemctl restart "$GX_TUNNEL_SERVICE"
    systemctl restart "$GX_WEBGUI_SERVICE"
    systemctl restart "$GX_MONITOR_SERVICE"
    sleep 2
    show_service_status
}

# List users function
list_tunnel_users() {
    echo -e "${WHITE}📋 SSH TUNNEL USERS${NC}"
    echo -e "${CYAN}───────────────────────────────────────────────────────────${NC}"
    
    local user_db=$(load_user_db)
    local users=$(echo "$user_db" | jq -r '.users[] | "\(.username)|\(.password)|\(.created)|\(.expires)|\(.max_connections)"' 2>/dev/null)
    
    if [ -z "$users" ]; then
        echo -e "${YELLOW}⚠️  No users found${NC}"
        return
    fi

    echo -e "${WHITE}┌─────────────────────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${WHITE}│ ${GREEN}Username${WHITE}     ${GREEN}Password${WHITE}     ${GREEN}Created${WHITE}     ${GREEN}Expires${WHITE}     ${GREEN}Max Conn${WHITE}     ${GREEN}Status${WHITE}    │${NC}"
    echo -e "${WHITE}├─────────────────────────────────────────────────────────────────────────────────┤${NC}"
    
    while IFS='|' read -r username password created expires max_conn; do
        # Check if account is expired
        if [ "$expires" != "null" ] && [ -n "$expires" ]; then
            current_ts=$(date +%s)
            expire_ts=$(date -d "$expires" +%s 2>/dev/null || echo 0)
            if [ $current_ts -gt $expire_ts ]; then
                status="${RED}EXPIRED${NC}"
            else
                days_left=$(( (expire_ts - current_ts) / 86400 ))
                status="${GREEN}$days_left days${NC}"
            fi
        else
            status="${GREEN}ACTIVE${NC}"
        fi
        
        printf "${WHITE}│ ${CYAN}%-12s ${YELLOW}%-12s ${BLUE}%-10s ${WHITE}%-10s ${PURPLE}%-12s ${WHITE}%-12s ${WHITE}│${NC}\n" \
               "$username" "$password" "$created" "${expires:-Never}" "$max_conn" "$status"
    done <<< "$users"
    
    echo -e "${WHITE}└─────────────────────────────────────────────────────────────────────────────────┘${NC}"
}

# Delete user function
delete_tunnel_user() {
    echo -e "${WHITE}🗑️  DELETE SSH TUNNEL USER${NC}"
    echo -e "${CYAN}───────────────────────────────────────────────────────────${NC}"
    
    local user_db=$(load_user_db)
    local users=$(echo "$user_db" | jq -r '.users[] | "\(.username) (\(.created))"')
    
    if [ -z "$users" ]; then
        echo -e "${YELLOW}⚠️  No users found${NC}"
        return
    fi
    
    echo -e "${YELLOW}Available users:${NC}"
    echo "$users" | nl -w 2 -s ') '
    echo
    
    read -p "Enter username to delete: " username
    
    if [ -z "$username" ]; then
        echo -e "${RED}❌ Username cannot be empty${NC}"
        return
    fi

    # Check if user exists
    local user_exists=$(echo "$user_db" | jq -r ".users[] | select(.username == \"$username\") | .username")
    
    if [ -z "$user_exists" ]; then
        echo -e "${RED}❌ User $username not found${NC}"
        return
    fi

    # Remove from database only
    local updated_db=$(echo "$user_db" | jq "del(.users[] | select(.username == \"$username\"))")
    save_user_db "$updated_db"
    
    echo -e "${GREEN}✅ User $username deleted successfully${NC}"
}

# System statistics
show_system_stats() {
    echo -e "${WHITE}💻 SYSTEM STATISTICS${NC}"
    echo -e "${CYAN}───────────────────────────────────────────────────────────${NC}"
    
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    local memory_info=$(free -m | awk 'NR==2{printf "%.2f%%", $3*100/$2}')
    local disk_usage=$(df -h / | awk 'NR==2{print $5}')
    local uptime=$(uptime -p)
    local server_ip=$(get_server_ip)
    local load_avg=$(uptime | awk -F'load average:' '{print $2}')
    
    echo -e "${WHITE}┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${WHITE}│ ${CYAN}📍 Server IP: ${YELLOW}$server_ip${WHITE}                         │${NC}"
    echo -e "${WHITE}│ ${CYAN}🖥️  CPU Usage: ${YELLOW}$cpu_usage%${WHITE}                               │${NC}"
    echo -e "${WHITE}│ ${CYAN}💾 Memory Usage: ${YELLOW}$memory_info${WHITE}                            │${NC}"
    echo -e "${WHITE}│ ${CYAN}💿 Disk Usage: ${YELLOW}$disk_usage${WHITE}                               │${NC}"
    echo -e "${WHITE}│ ${CYAN}📊 Load Average: ${YELLOW}$load_avg${WHITE}                           │${NC}"
    echo -e "${WHITE}│ ${CYAN}⏱️  Uptime: ${YELLOW}$uptime${WHITE}                           │${NC}"
    echo -e "${WHITE}└─────────────────────────────────────────────────────────┘${NC}"
}

# User statistics
show_user_statistics() {
    echo -e "${WHITE}📊 USER STATISTICS${NC}"
    echo -e "${CYAN}───────────────────────────────────────────────────────────${NC}"
    
    if [ -f "$STATS_DB" ]; then
        echo -e "${YELLOW}User Connection Statistics:${NC}"
        sqlite3 -header -column "$STATS_DB" "SELECT username, connections, download_bytes, upload_bytes FROM user_stats ORDER BY connections DESC LIMIT 10;" 2>/dev/null || echo "No user statistics available"
    else
        echo -e "${RED}Statistics database not found${NC}"
    fi
}

# Real-time logs
show_realtime_logs() {
    echo -e "${WHITE}📋 REAL-TIME LOGS${NC}"
    echo -e "${CYAN}───────────────────────────────────────────────────────────${NC}"
    echo -e "${YELLOW}Press Ctrl+C to stop viewing logs${NC}"
    echo
    
    local log_file="$LOG_DIR/websocket.log"
    if [ -f "$log_file" ]; then
        tail -f "$log_file" | while read line; do
            if [[ $line == *"ERROR"* ]] || [[ $line == *"Failed"* ]]; then
                echo -e "${RED}$line${NC}"
            elif [[ $line == *"WARNING"* ]]; then
                echo -e "${YELLOW}$line${NC}"
            elif [[ $line == *"Authentication"* ]] && [[ $line == *"successfully"* ]]; then
                echo -e "${GREEN}$line${NC}"
            elif [[ $line == *"New tunnel"* ]]; then
                echo -e "${BLUE}$line${NC}"
            elif [[ $line == *"Connected"* ]]; then
                echo -e "${CYAN}$line${NC}"
            else
                echo -e "${WHITE}$line${NC}"
            fi
        done
    else
        echo -e "${RED}Log file not found: $log_file${NC}"
    fi
}

# Check dependencies
check_dependencies() {
    local deps=("systemctl" "jq" "sqlite3")
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo -e "${RED}❌ Missing dependency: $dep${NC}"
            exit 1
        fi
    done
}

# Main execution
main() {
    check_root
    check_dependencies
    show_main_menu
}

# Handle command line arguments
case "${1:-}" in
    "menu")
        main
        ;;
    "start")
        start_services
        ;;
    "stop")
        stop_services
        ;;
    "restart")
        restart_services
        ;;
    "status")
        show_service_status
        ;;
    "add-user")
        add_tunnel_user
        ;;
    "list-users")
        list_tunnel_users
        ;;
    "stats")
        show_enhanced_stats
        ;;
    "monitor")
        show_monitor
        ;;
    "backup")
        backup_system
        ;;
    "update")
        update_system
        ;;
    "logs")
        show_realtime_logs
        ;;
    *)
        echo -e "${GREEN}Usage: $0 {menu|start|stop|restart|status|add-user|list-users|stats|monitor|backup|update|logs}${NC}"
        echo
        echo -e "${WHITE}Enhanced Commands:${NC}"
        echo -e "  ${CYAN}menu${NC}       - Show interactive menu"
        echo -e "  ${CYAN}start${NC}      - Start all services"
        echo -e "  ${CYAN}stop${NC}       - Stop all services"
        echo -e "  ${CYAN}restart${NC}    - Restart all services"
        echo -e "  ${CYAN}status${NC}     - Show service status"
        echo -e "  ${CYAN}add-user${NC}   - Add new tunnel user"
        echo -e "  ${CYAN}list-users${NC} - List all users"
        echo -e "  ${CYAN}stats${NC}      - Show enhanced statistics"
        echo -e "  ${CYAN}monitor${NC}    - Real-time monitoring"
        echo -e "  ${CYAN}backup${NC}     - Backup system"
        echo -e "  ${CYAN}update${NC}     - Update system"
        echo -e "  ${CYAN}logs${NC}       - Show real-time logs"
        exit 1
        ;;
esac
EOF

    chmod +x /usr/local/bin/gx-tunnel
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
    python3 -c "import flask, flask_cors, psutil, requests, socketio, eventlet" > /dev/null 2>&1 || { 
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
    systemctl start "$SERVICE_NAME" "$WEBGUI_SERVICE" "gx-monitor"
    
    sleep 5
    
    local tunnel_status=$(systemctl is-active "$SERVICE_NAME")
    local webgui_status=$(systemctl is-active "$WEBGUI_SERVICE")
    local monitor_status=$(systemctl is-active "gx-monitor")
    
    if [ "$tunnel_status" = "active" ] && [ "$webgui_status" = "active" ]; then
        show_success_banner "All services started successfully"
        log_info "Monitor service status: $monitor_status"
        return 0
    else
        log_warning "Services partially started (Tunnel: $tunnel_status, WebGUI: $webgui_status)"
        log_info "Checking service logs for details..."
        journalctl -u "$SERVICE_NAME" -u "$WEBGUI_SERVICE" --no-pager -n 10
        return 1
    fi
}

# Create SSL certificate (optional)
create_ssl_certificate() {
    show_progress_banner "13" "Setting Up SSL (Optional)"
    
    local domain=$(jq -r '.server.domain' "$CONFIG_FILE" 2>/dev/null)
    local ssl_enabled=$(jq -r '.server.ssl_enabled' "$CONFIG_FILE" 2>/dev/null)
    
    if [ "$ssl_enabled" = "true" ] && [ -n "$domain" ] && [ "$domain" != "null" ]; then
        log_info "SSL enabled for domain: $domain"
        log_info "To set up SSL certificate, run:"
        echo -e "${YELLOW}  certbot --nginx -d $domain${NC}"
        echo -e "${YELLOW}  Then update $CONFIG_FILE with SSL certificate paths${NC}"
    else
        log_info "SSL not configured. You can enable it later in the Web GUI"
    fi
    
    echo
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
    echo -e "  ${BLUE}└─ ${GREEN}✅ Enhanced Fail2Ban Protection${NC}"
    echo -e "  ${BLUE}└─ ${GREEN}✅ Advanced DDoS Protection${NC}"
    echo -e "  ${BLUE}└─ ${GREEN}✅ Auto Backup System${NC}"
    echo -e "  ${BLUE}└─ ${GREEN}✅ Rate Limiting${NC}"
    echo -e "  ${BLUE}└─ ${GREEN}✅ Connection Monitoring${NC}"
    echo
    echo -e "${WHITE}🚀 ${CYAN}Enhanced Commands:${NC}"
    echo -e "  ${GREEN}└─ gx-tunnel menu${NC}         - Interactive menu"
    echo -e "  ${GREEN}└─ gx-tunnel start${NC}        - Start services"
    echo -e "  ${GREEN}└─ gx-tunnel status${NC}       - Service status"
    echo -e "  ${GREEN}└─ gx-tunnel add-user${NC}     - Add tunnel user"
    echo -e "  ${GREEN}└─ gx-tunnel backup${NC}       - Create backup"
    echo -e "  ${GREEN}└─ gx-tunnel update${NC}       - Update system"
    echo -e "  ${GREEN}└─ gx-tunnel stats${NC}        - Show statistics"
    echo -e "  ${GREEN}└─ gx-tunnel monitor${NC}      - Real-time monitor"
    echo -e "  ${GREEN}└─ gx-tunnel logs${NC}         - View logs"
    echo
    echo -e "${WHITE}⏰ ${CYAN}Next Steps:${NC}"
    echo -e "  ${BLUE}1. ${YELLOW}Access Web GUI: ${GREEN}http://$server_ip:8081${NC}"
    echo -e "  ${BLUE}2. ${YELLOW}Add user: ${GREEN}gx-tunnel add-user${NC}"
    echo -e "  ${BLUE}3. ${YELLOW}Check status: ${GREEN}gx-tunnel status${NC}"
    echo -e "  ${BLUE}4. ${YELLOW}Monitor: ${GREEN}gx-tunnel monitor${NC}"
    echo -e "  ${BLUE}5. ${YELLOW}Configure domain & SSL in Web GUI${NC}"
    echo
    echo -e "${PURPLE}💫 ${WHITE}Thank you for choosing GX Tunnel!${NC}"
    echo
}

# Main installation function
main() {
    display_banner
    echo
    echo -e "${GREEN}🚀 [GX TUNNEL] Starting enhanced installation...${NC}"
    echo
    
    # Execute installation steps
    check_root
    clean_previous_installation
    install_dependencies
    install_python_packages
    create_directories
    copy_local_files
    create_backup_script
    create_update_script
    create_monitoring_script
    create_enhanced_management_script
    create_services
    setup_firewall
    setup_fail2ban
    setup_log_rotation
    create_ssl_certificate
    
    # Verify and start
    if verify_installation; then
        if start_services; then
            show_installation_summary
            
            # Display important notes
            echo -e "${YELLOW}📝 Important Notes:${NC}"
            echo -e "  ${WHITE}• ${CYAN}Auto-backup runs daily${NC}"
            echo -e "  ${WHITE}• ${CYAN}Real-time monitoring enabled${NC}"
            echo -e "  ${WHITE}• ${CYAN}Enhanced security features active${NC}"
            echo -e "  ${WHITE}• ${CYAN}Web GUI with full API support${NC}"
            echo -e "  ${WHITE}• ${CYAN}No system users - JSON database only${NC}"
            echo
            echo -e "${GREEN}🔧 For support: ${YELLOW}Telegram: @jawadx${NC}"
            echo
            
        else
            log_warning "Services started with issues, but installation completed"
            show_installation_summary
        fi
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
