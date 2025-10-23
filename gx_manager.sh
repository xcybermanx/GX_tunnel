#!/bin/bash

# GX Tunnel Management Script
# Created by Jawad - Telegram: @jawadx

# Constants
GX_TUNNEL_SERVICE="gx-tunnel"
GX_WEBGUI_SERVICE="gx-webgui"
INSTALL_DIR="/opt/gx_tunnel"
PYTHON_SCRIPT_PATH="$INSTALL_DIR/gx_websocket.py"
WEBGUI_SCRIPT_PATH="$INSTALL_DIR/webgui.py"
LOG_FILE="/var/log/gx_tunnel/websocket.log"
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

# Function to get server IP
get_server_ip() {
    local ipv4=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -1)
    if [ -n "$ipv4" ]; then
        echo "$ipv4"
    else
        echo "unknown"
    fi
}

# Function to load user database
load_user_db() {
    if [ -f "$USER_DB" ]; then
        cat "$USER_DB"
    else
        echo '{"users": [], "settings": {}}'
    fi
}

# Function to save user database
save_user_db() {
    local data="$1"
    echo "$data" > "$USER_DB"
    chmod 600 "$USER_DB"
}

# Function to add user with proper error handling
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

    # Create system user with nologin shell
    if useradd -m -s /usr/sbin/nologin "$username" 2>/dev/null; then
        if echo "$username:$password" | chpasswd 2>/dev/null; then
            # Add to user database
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
        else
            userdel -r "$username" 2>/dev/null
            echo -e "${RED}❌ Failed to set password${NC}"
        fi
    else
        echo -e "${RED}❌ Failed to create user${NC}"
    fi
}

# Function to show user configuration
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

# Function to delete user
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

    # Delete from system
    if userdel -r "$username" 2>/dev/null; then
        # Remove from database
        local updated_db=$(echo "$user_db" | jq "del(.users[] | select(.username == \"$username\"))")
        save_user_db "$updated_db"
        
        echo -e "${GREEN}✅ User $username deleted successfully${NC}"
    else
        echo -e "${RED}❌ Failed to delete user $username${NC}"
    fi
}

# Function to list users with details
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

# Function to show service status
show_service_status() {
    echo -e "${WHITE}📊 SERVICE STATUS${NC}"
    echo -e "${CYAN}───────────────────────────────────────────────────────────${NC}"
    
    local server_ip=$(get_server_ip)
    local tunnel_status=$(systemctl is-active "$GX_TUNNEL_SERVICE")
    local webgui_status=$(systemctl is-active "$GX_WEBGUI_SERVICE")
    
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
    
    echo -e "${WHITE}│ ${CYAN}📍 Server IP: ${YELLOW}$server_ip${WHITE}                         │${NC}"
    echo -e "${WHITE}│ ${CYAN}🌐 Tunnel Port: ${YELLOW}8080${WHITE}                               │${NC}"
    echo -e "${WHITE}│ ${CYAN}🖥️  Web GUI Port: ${YELLOW}8081${WHITE}                              │${NC}"
    echo -e "${WHITE}└─────────────────────────────────────────────────────────┘${NC}"
}

# Function to show VPS statistics
show_vps_stats() {
    echo -e "${WHITE}💻 VPS STATISTICS${NC}"
    echo -e "${CYAN}───────────────────────────────────────────────────────────${NC}"
    
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    local memory_info=$(free -m | awk 'NR==2{printf "%.2f%%", $3*100/$2}')
    local disk_usage=$(df -h / | awk 'NR==2{print $5}')
    local uptime=$(uptime -p)
    local server_ip=$(get_server_ip)
    
    echo -e "${WHITE}┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${WHITE}│ ${CYAN}📍 Server IP: ${YELLOW}$server_ip${WHITE}                         │${NC}"
    echo -e "${WHITE}│ ${CYAN}🖥️  CPU Usage: ${YELLOW}$cpu_usage%${WHITE}                               │${NC}"
    echo -e "${WHITE}│ ${CYAN}💾 Memory Usage: ${YELLOW}$memory_info${WHITE}                            │${NC}"
    echo -e "${WHITE}│ ${CYAN}💿 Disk Usage: ${YELLOW}$disk_usage${WHITE}                               │${NC}"
    echo -e "${WHITE}│ ${CYAN}⏱️  Uptime: ${YELLOW}$uptime${WHITE}                           │${NC}"
    echo -e "${WHITE}└─────────────────────────────────────────────────────────┘${NC}"
}

# Function to start services
start_services() {
    echo -e "${WHITE}🚀 STARTING GX TUNNEL SERVICES${NC}"
    echo -e "${CYAN}───────────────────────────────────────────────────────────${NC}"
    
    systemctl start "$GX_TUNNEL_SERVICE"
    systemctl start "$GX_WEBGUI_SERVICE"
    sleep 2
    show_service_status
}

# Function to stop services
stop_services() {
    echo -e "${WHITE}🛑 STOPPING GX TUNNEL SERVICES${NC}"
    echo -e "${CYAN}───────────────────────────────────────────────────────────${NC}"
    
    systemctl stop "$GX_TUNNEL_SERVICE"
    systemctl stop "$GX_WEBGUI_SERVICE"
    sleep 2
    show_service_status
}

# Function to restart services
restart_services() {
    echo -e "${WHITE}🔄 RESTARTING GX TUNNEL SERVICES${NC}"
    echo -e "${CYAN}───────────────────────────────────────────────────────────${NC}"
    
    systemctl restart "$GX_TUNNEL_SERVICE"
    systemctl restart "$GX_WEBGUI_SERVICE"
    sleep 2
    show_service_status
}

# Function to show real-time logs
show_realtime_logs() {
    echo -e "${WHITE}📋 REAL-TIME LOGS${NC}"
    echo -e "${CYAN}───────────────────────────────────────────────────────────${NC}"
    echo -e "${YELLOW}Press Ctrl+C to stop viewing logs${NC}"
    echo
    
    if [ -f "$LOG_FILE" ]; then
        tail -f "$LOG_FILE" | while read line; do
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
        echo -e "${RED}Log file not found: $LOG_FILE${NC}"
    fi
}

# Main menu function
show_main_menu() {
    while true; do
        show_header
        
        echo -e "${WHITE}🏠 MAIN MENU${NC}"
        echo -e "${CYAN}───────────────────────────────────────────────────────────${NC}"
        echo -e "${WHITE}1) ${GREEN}👤 User Management${NC}"
        echo -e "${WHITE}2) ${YELLOW}🚀 Service Control${NC}"
        echo -e "${WHITE}3) ${BLUE}📊 Service Status${NC}"
        echo -e "${WHITE}4) ${PURPLE}💻 VPS Statistics${NC}"
        echo -e "${WHITE}5) ${CYAN}📋 View Users${NC}"
        echo -e "${WHITE}6) ${WHITE}📜 Real-time Logs${NC}"
        echo -e "${WHITE}7) ${GREEN}🔄 Restart Services${NC}"
        echo -e "${WHITE}8) ${RED}🛑 Stop Services${NC}"
        echo -e "${WHITE}0) ${RED}❌ Exit${NC}"
        echo -e "${CYAN}───────────────────────────────────────────────────────────${NC}"
        
        read -p "Enter your choice [0-8]: " choice
        
        case $choice in
            1)
                show_user_management_menu
                ;;
            2)
                start_services
                read -p "Press Enter to continue..."
                ;;
            3)
                show_service_status
                read -p "Press Enter to continue..."
                ;;
            4)
                show_vps_stats
                read -p "Press Enter to continue..."
                ;;
            5)
                list_tunnel_users
                read -p "Press Enter to continue..."
                ;;
            6)
                show_realtime_logs
                ;;
            7)
                restart_services
                read -p "Press Enter to continue..."
                ;;
            8)
                stop_services
                read -p "Press Enter to continue..."
                ;;
            0)
                echo -e "${GREEN}👋 Thank you for using GX Tunnel!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}❌ Invalid choice. Please try again.${NC}"
                sleep 2
                ;;
        esac
    done
}

# User management menu
show_user_management_menu() {
    while true; do
        show_header
        
        echo -e "${WHITE}👤 USER MANAGEMENT${NC}"
        echo -e "${CYAN}───────────────────────────────────────────────────────────${NC}"
        echo -e "${WHITE}1) ${GREEN}➕ Add User${NC}"
        echo -e "${WHITE}2) ${RED}🗑️  Delete User${NC}"
        echo -e "${WHITE}3) ${BLUE}📋 List Users${NC}"
        echo -e "${WHITE}4) ${YELLOW}🔙 Back to Main Menu${NC}"
        echo -e "${CYAN}───────────────────────────────────────────────────────────${NC}"
        
        read -p "Enter your choice [1-4]: " choice
        
        case $choice in
            1)
                add_tunnel_user
                read -p "Press Enter to continue..."
                ;;
            2)
                delete_tunnel_user
                read -p "Press Enter to continue..."
                ;;
            3)
                list_tunnel_users
                read -p "Press Enter to continue..."
                ;;
            4)
                break
                ;;
            *)
                echo -e "${RED}❌ Invalid choice. Please try again.${NC}"
                sleep 2
                ;;
        esac
    done
}

# Check dependencies
check_dependencies() {
    local deps=("systemctl" "jq" "sqlite3" "useradd" "chpasswd")
    
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
        show_vps_stats
        ;;
    "logs")
        show_realtime_logs
        ;;
    *)
        echo -e "${GREEN}Usage: $0 {menu|start|stop|restart|status|add-user|list-users|stats|logs}${NC}"
        echo
        echo -e "${WHITE}Commands:${NC}"
        echo -e "  ${CYAN}menu${NC}       - Show interactive menu"
        echo -e "  ${CYAN}start${NC}      - Start services"
        echo -e "  ${CYAN}stop${NC}       - Stop services"
        echo -e "  ${CYAN}restart${NC}    - Restart services"
        echo -e "  ${CYAN}status${NC}     - Show service status"
        echo -e "  ${CYAN}add-user${NC}   - Add new tunnel user"
        echo -e "  ${CYAN}list-users${NC} - List all users"
        echo -e "  ${CYAN}stats${NC}      - Show VPS statistics"
        echo -e "  ${CYAN}logs${NC}       - Show real-time logs"
        exit 1
        ;;
esac
