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

# ... [Previous banner and utility functions remain the same] ...

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
        nodejs \
        npm \
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

    # Update npm to latest version
    log_info "Updating npm..."
    npm install -g npm@latest --quiet

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

# Install Node.js packages for web GUI
install_node_packages() {
    show_progress_banner "4a" "Installing Node.js Packages"
    
    log_info "Installing Node.js dependencies for web GUI..."
    
    # Create package.json for web GUI
    cat > "$INSTALL_DIR/package.json" << 'EOF'
{
  "name": "gx-tunnel-webgui",
  "version": "1.0.0",
  "description": "GX Tunnel Web GUI",
  "main": "webgui.js",
  "scripts": {
    "start": "node webgui.js",
    "test": "echo \"Error: no test specified\" && exit 1"
  },
  "dependencies": {
    "express": "^4.18.2",
    "express-session": "^1.17.3",
    "cors": "^2.8.5",
    "body-parser": "^1.20.2",
    "sqlite3": "^5.1.6",
    "child_process": "^1.0.2"
  },
  "keywords": ["tunnel", "websocket", "ssh", "admin"],
  "author": "Jawad",
  "license": "MIT"
}
EOF

    # Install npm packages
    cd "$INSTALL_DIR"
    npm install --quiet --production
    
    show_success_banner "Node.js packages installed successfully"
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
    if [ -f "$SCRIPT_DIR/webgui.js" ]; then
        cp "$SCRIPT_DIR/webgui.js" "$INSTALL_DIR/webgui.js"
        log_success "Web GUI script copied"
    else
        log_error "webgui.js not found in current directory"
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

    log_info "Creating web GUI service (Node.js)..."
    cat > /etc/systemd/system/"$WEBGUI_SERVICE".service << EOF
[Unit]
Description=GX Tunnel Web GUI (Node.js)
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/node $INSTALL_DIR/webgui.js
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
Environment=NODE_ENV=production
Environment=PORT=8081

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

# Update the enhanced management script to handle Node.js web GUI
create_enhanced_management_script() {
    log_info "Creating enhanced management script..."
    
    # Update the service status check in the management script
    cat > /usr/local/bin/gx-tunnel << 'EOF'
#!/bin/bash

# GX Tunnel Enhanced Management Script
# Created by Jawad - Telegram: @jawadx

# ... [Previous code remains the same until service status section] ...

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
        echo -e "${WHITE}│ ${GREEN}🟢 Tunnel Service (Python): ${GREEN}ACTIVE${WHITE}                   │${NC}"
    else
        echo -e "${WHITE}│ ${RED}🔴 Tunnel Service (Python): ${RED}INACTIVE${WHITE}                 │${NC}"
    fi
    
    if [ "$webgui_status" = "active" ]; then
        echo -e "${WHITE}│ ${GREEN}🟢 Web GUI (Node.js): ${GREEN}ACTIVE${WHITE}                        │${NC}"
    else
        echo -e "${WHITE}│ ${RED}🔴 Web GUI (Node.js): ${RED}INACTIVE${WHITE}                      │${NC}"
    fi
    
    if [ "$monitor_status" = "active" ]; then
        echo -e "${WHITE}│ ${GREEN}🟢 Monitor: ${GREEN}ACTIVE${WHITE}                                │${NC}"
    else
        echo -e "${WHITE}│ ${YELLOW}🟡 Monitor: ${YELLOW}INACTIVE${WHITE}                             │${NC}"
    fi
    
    echo -e "${WHITE}│ ${CYAN}📍 Server IP: ${YELLOW}$server_ip${WHITE}                         │${NC}"
    echo -e "${WHITE}│ ${CYAN}🌐 Tunnel Port: ${YELLOW}8080${WHITE}                               │${NC}"
    echo -e "${WHITE}│ ${CYAN}🖥️  Web GUI Port: ${YELLOW}8081${WHITE}                              │${NC}"
    echo -e "${WHITE}│ ${CYAN}🔧 Web GUI Technology: ${YELLOW}Node.js${WHITE}                        │${NC}"
    echo -e "${WHITE}└─────────────────────────────────────────────────────────┘${NC}"
}

# ... [Rest of the management script remains the same] ...
EOF

    chmod +x /usr/local/bin/gx-tunnel
}

# Update the update script to handle Node.js files
create_update_script() {
    log_info "Creating enhanced update script..."
    cat > "$INSTALL_DIR/update.sh" << 'EOF'
#!/bin/bash

# GX Tunnel Update Script
# Created by Jawad - Telegram: @jawadx

# ... [Previous code remains the same] ...

# Download updated files
if download_file "https://raw.githubusercontent.com/xcybermanx/GX_tunnel/main/gx_websocket.py" "gx_websocket.py.new" &&
   download_file "https://raw.githubusercontent.com/xcybermanx/GX_tunnel/main/webgui.js" "webgui.js.new" &&
   download_file "https://raw.githubusercontent.com/xcybermanx/GX_tunnel/main/gx_manager.sh" "/usr/local/bin/gx-tunnel.new"; then

    # Verify downloads
    if [ -s "gx_websocket.py.new" ] && [ -s "webgui.js.new" ] && [ -s "/usr/local/bin/gx-tunnel.new" ]; then
        echo "✅ Files downloaded successfully"
        log "Update files downloaded successfully"
        
        # Replace old files
        mv "gx_websocket.py.new" "gx_websocket.py"
        mv "webgui.js.new" "webgui.js"
        mv "/usr/local/bin/gx-tunnel.new" "/usr/local/bin/gx-tunnel"
        chmod +x "/usr/local/bin/gx-tunnel"
        
        # Install/update Node.js dependencies if webgui.js changed
        echo "📦 Updating Node.js dependencies..."
        cd "$INSTALL_DIR"
        npm install --quiet --production
        
        # Restart services
        echo "🔧 Restarting services..."
        systemctl restart gx-tunnel gx-webgui gx-monitor
        
        # ... [Rest of the update script remains the same] ...
EOF

    chmod +x "$INSTALL_DIR/update.sh"
}

# Update main installation function to include Node.js package installation
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
    install_node_packages  # Add this line
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
    
    # ... [Rest of main function remains the same] ...
}

# ... [Rest of the script remains the same] ...
