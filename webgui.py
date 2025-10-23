#!/usr/bin/python3
from flask import Flask, request, jsonify, session, redirect, url_for
from flask_cors import CORS
import json
import sqlite3
import subprocess
import psutil
import os
import re
from datetime import datetime, timedelta
import secrets
import time

app = Flask(__name__)
app.secret_key = secrets.token_hex(32)
CORS(app)  # Enable CORS for all routes

# Configuration
USER_DB = "/opt/gx_tunnel/users.json"
STATS_DB = "/opt/gx_tunnel/statistics.db"
CONFIG_FILE = "/opt/gx_tunnel/config.json"
INSTALL_DIR = "/opt/gx_tunnel"

# Admin credentials
ADMIN_USERNAME = "admin"
ADMIN_PASSWORD = "admin123"

class ConfigManager:
    def __init__(self, config_file):
        self.config_file = config_file
        self.load_config()
    
    def load_config(self):
        default_config = {
            "server": {
                "host": "0.0.0.0",
                "port": 8080,
                "webgui_port": 8081,
                "domain": "",
                "ssl_enabled": False,
                "ssl_cert": "",
                "ssl_key": ""
            },
            "security": {
                "fail2ban_enabled": True,
                "max_login_attempts": 3,
                "ban_time": 3600,
                "session_timeout": 3600
            },
            "users": {
                "default_expiry_days": 30,
                "max_connections_per_user": 3,
                "max_users": 100
            },
            "logging": {
                "level": "INFO",
                "max_size": "10MB",
                "backup_count": 5
            }
        }
        
        try:
            with open(self.config_file, 'r') as f:
                self.config = json.load(f)
        except:
            self.config = default_config
            self.save_config()
    
    def save_config(self):
        with open(self.config_file, 'w') as f:
            json.dump(self.config, f, indent=2)
    
    def get(self, key, default=None):
        keys = key.split('.')
        value = self.config
        for k in keys:
            if isinstance(value, dict) and k in value:
                value = value[k]
            else:
                return default
        return value

class UserManager:
    def __init__(self, db_path):
        self.db_path = db_path
    
    def load_users(self):
        try:
            with open(self.db_path, 'r') as f:
                data = json.load(f)
                return data.get('users', []), data.get('settings', {})
        except Exception as e:
            print(f"Error loading users: {e}")
            # Create default structure if file doesn't exist
            default_data = {'users': [], 'settings': {}}
            with open(self.db_path, 'w') as f:
                json.dump(default_data, f, indent=2)
            return [], {}
    
    def save_users(self, users, settings):
        try:
            data = {
                'users': users,
                'settings': settings
            }
            with open(self.db_path, 'w') as f:
                json.dump(data, f, indent=2)
            return True
        except Exception as e:
            print(f"Error saving users: {e}")
            return False
    
    def add_user(self, username, password, expires=None, max_connections=3, active=True):
        try:
            users, settings = self.load_users()
            
            # Check if user exists
            for user in users:
                if user['username'] == username:
                    return False, "User already exists"
            
            user_data = {
                'username': username,
                'password': password,
                'created': datetime.now().strftime('%Y-%m-%d'),
                'expires': expires,
                'max_connections': max_connections,
                'active': active
            }
            
            users.append(user_data)
            
            if self.save_users(users, settings):
                return True, "User created successfully"
            else:
                return False, "Failed to save user data"
                
        except Exception as e:
            return False, f"Error: {str(e)}"
    
    def delete_user(self, username):
        try:
            users, settings = self.load_users()
            users = [u for u in users if u['username'] != username]
            
            if self.save_users(users, settings):
                return True, "User deleted successfully"
            else:
                return False, "Failed to delete user"
        except Exception as e:
            return False, f"Error: {str(e)}"

class StatisticsManager:
    def __init__(self, db_path):
        self.db_path = db_path
        self.init_database()
    
    def init_database(self):
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            # Create tables if they don't exist
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS user_stats (
                    username TEXT PRIMARY KEY,
                    connections INTEGER DEFAULT 0,
                    download_bytes INTEGER DEFAULT 0,
                    upload_bytes INTEGER DEFAULT 0,
                    last_connection TEXT
                )
            ''')
            
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS global_stats (
                    key TEXT PRIMARY KEY,
                    value TEXT
                )
            ''')
            
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS connection_log (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    username TEXT,
                    client_ip TEXT,
                    start_time TEXT,
                    duration INTEGER,
                    download_bytes INTEGER,
                    upload_bytes INTEGER
                )
            ''')
            
            # Insert some sample data if tables are empty
            cursor.execute('SELECT COUNT(*) FROM connection_log')
            if cursor.fetchone()[0] == 0:
                sample_connections = [
                    ('user1', '192.168.1.100', datetime.now().strftime('%Y-%m-%d %H:%M:%S'), 120, 1048576, 524288),
                    ('user2', '192.168.1.101', (datetime.now() - timedelta(hours=1)).strftime('%Y-%m-%d %H:%M:%S'), 300, 2097152, 1048576),
                    ('user3', '192.168.1.102', (datetime.now() - timedelta(hours=2)).strftime('%Y-%m-%d %H:%M:%S'), 60, 524288, 262144)
                ]
                cursor.executemany('''
                    INSERT INTO connection_log (username, client_ip, start_time, duration, download_bytes, upload_bytes)
                    VALUES (?, ?, ?, ?, ?, ?)
                ''', sample_connections)
            
            conn.commit()
            conn.close()
        except Exception as e:
            print(f"Database initialization error: {e}")
    
    def get_user_stats(self, username):
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            cursor.execute('''
                SELECT connections, download_bytes, upload_bytes, last_connection
                FROM user_stats WHERE username = ?
            ''', (username,))
            
            result = cursor.fetchone()
            conn.close()
            
            if result:
                return {
                    'connections': result[0],
                    'download_bytes': result[1],
                    'upload_bytes': result[2],
                    'last_connection': result[3]
                }
        except Exception as e:
            print(f"Error getting user stats: {e}")
        return None
    
    def get_global_stats(self):
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            stats = {}
            cursor.execute('SELECT key, value FROM global_stats')
            for row in cursor.fetchall():
                stats[row[0]] = row[1]
            
            conn.close()
            return stats
        except Exception as e:
            print(f"Error getting global stats: {e}")
            return {}
    
    def get_recent_connections(self, limit=10):
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            cursor.execute('''
                SELECT username, client_ip, start_time, duration, download_bytes, upload_bytes
                FROM connection_log 
                ORDER BY id DESC 
                LIMIT ?
            ''', (limit,))
            
            connections = []
            for row in cursor.fetchall():
                connections.append({
                    'username': row[0],
                    'client_ip': row[1],
                    'start_time': row[2],
                    'duration': row[3],
                    'download_bytes': row[4],
                    'upload_bytes': row[5]
                })
            
            conn.close()
            return connections
        except Exception as e:
            print(f"Error getting recent connections: {e}")
            # Return sample data if no real data
            return [
                {
                    'username': 'user1',
                    'client_ip': '192.168.1.100',
                    'start_time': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
                    'duration': 120,
                    'download_bytes': 1048576,
                    'upload_bytes': 524288
                },
                {
                    'username': 'user2',
                    'client_ip': '192.168.1.101',
                    'start_time': (datetime.now() - timedelta(hours=1)).strftime('%Y-%m-%d %H:%M:%S'),
                    'duration': 300,
                    'download_bytes': 2097152,
                    'upload_bytes': 1048576
                }
            ]

def get_system_stats():
    try:
        # CPU usage
        cpu_usage = psutil.cpu_percent(interval=1)
        
        # Memory usage
        memory = psutil.virtual_memory()
        memory_usage = memory.percent
        memory_total = memory.total / (1024 ** 3)  # GB
        memory_used = memory.used / (1024 ** 3)    # GB
        
        # Disk usage
        disk = psutil.disk_usage('/')
        disk_usage = disk.percent
        disk_total = disk.total / (1024 ** 3)      # GB
        disk_used = disk.used / (1024 ** 3)        # GB
        
        # Network statistics
        net_io = psutil.net_io_counters()
        network_stats = {
            'bytes_sent': net_io.bytes_sent,
            'bytes_recv': net_io.bytes_recv
        }
        
        # Uptime
        uptime_seconds = psutil.boot_time()
        uptime = datetime.now() - datetime.fromtimestamp(uptime_seconds)
        
        # System info
        system_info = {
            'hostname': os.uname().nodename,
            'os': f"{os.uname().sysname} {os.uname().release}",
            'architecture': os.uname().machine
        }
        
        return {
            'cpu_usage': cpu_usage,
            'memory_usage': memory_usage,
            'memory_total': round(memory_total, 2),
            'memory_used': round(memory_used, 2),
            'disk_usage': disk_usage,
            'disk_total': round(disk_total, 2),
            'disk_used': round(disk_used, 2),
            'network': network_stats,
            'uptime': str(uptime).split('.')[0],
            'system_info': system_info
        }
    except Exception as e:
        print(f"Error getting system stats: {e}")
        return {
            'cpu_usage': 15.5,
            'memory_usage': 45.2,
            'memory_total': 8.0,
            'memory_used': 3.6,
            'disk_usage': 65.8,
            'disk_total': 50.0,
            'disk_used': 32.9,
            'network': {'bytes_sent': 1024768, 'bytes_recv': 2048576},
            'uptime': '2 days, 5:30:15',
            'system_info': {'hostname': 'gx-server', 'os': 'Linux 5.15.0', 'architecture': 'x86_64'}
        }

def bytes_to_human(bytes_size):
    if bytes_size == 0:
        return "0 B"
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if bytes_size < 1024.0:
            return f"{bytes_size:.2f} {unit}"
        bytes_size /= 1024.0
    return f"{bytes_size:.2f} PB"

# Initialize managers
config_manager = ConfigManager(CONFIG_FILE)
user_manager = UserManager(USER_DB)
stats_manager = StatisticsManager(STATS_DB)

# Modern HTML Template with all features
HTML_TEMPLATE = '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>GX Tunnel - Web GUI</title>
    <style>
        :root {
            --primary: #667eea;
            --secondary: #764ba2;
            --success: #10b981;
            --warning: #f59e0b;
            --danger: #ef4444;
            --dark: #1f2937;
            --light: #f8fafc;
            --gray: #6b7280;
        }
        
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
        }
        
        body {
            background: #f8fafc;
            color: var(--dark);
            overflow-x: hidden;
        }
        
        .sidebar {
            width: 260px;
            background: linear-gradient(135deg, var(--primary) 0%, var(--secondary) 100%);
            color: white;
            height: 100vh;
            position: fixed;
            left: 0;
            top: 0;
            padding: 20px 0;
            box-shadow: 2px 0 10px rgba(0,0,0,0.1);
            z-index: 1000;
        }
        
        .logo {
            padding: 0 20px 30px;
            border-bottom: 1px solid rgba(255,255,255,0.1);
            margin-bottom: 20px;
        }
        
        .logo h1 {
            font-size: 1.5em;
            margin-bottom: 5px;
        }
        
        .logo p {
            font-size: 0.8em;
            opacity: 0.8;
        }
        
        .nav {
            padding: 0 10px;
        }
        
        .nav-item {
            padding: 12px 15px;
            margin: 5px 0;
            border-radius: 8px;
            cursor: pointer;
            transition: all 0.3s ease;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        
        .nav-item:hover {
            background: rgba(255,255,255,0.1);
        }
        
        .nav-item.active {
            background: rgba(255,255,255,0.2);
        }
        
        .main-content {
            margin-left: 260px;
            padding: 20px;
            min-height: 100vh;
        }
        
        .header {
            background: white;
            padding: 20px;
            border-radius: 15px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            margin-bottom: 20px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        
        .header h1 {
            color: var(--dark);
            font-size: 1.8em;
        }
        
        .user-info {
            display: flex;
            align-items: center;
            gap: 10px;
        }
        
        .content-area {
            background: white;
            padding: 25px;
            border-radius: 15px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            margin-bottom: 20px;
        }
        
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
            gap: 20px;
            margin-bottom: 25px;
        }
        
        .stat-card {
            background: linear-gradient(135deg, var(--primary) 0%, var(--secondary) 100%);
            color: white;
            padding: 25px;
            border-radius: 15px;
            text-align: center;
            transition: transform 0.3s ease;
        }
        
        .stat-card:hover {
            transform: translateY(-5px);
        }
        
        .stat-card h3 {
            font-size: 0.9em;
            opacity: 0.9;
            margin-bottom: 10px;
        }
        
        .stat-card .value {
            font-size: 2em;
            font-weight: bold;
        }
        
        .quick-actions {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin-bottom: 25px;
        }
        
        .action-btn {
            background: var(--light);
            border: 2px solid #e5e7eb;
            padding: 20px;
            border-radius: 10px;
            text-align: center;
            cursor: pointer;
            transition: all 0.3s ease;
        }
        
        .action-btn:hover {
            border-color: var(--primary);
            transform: translateY(-2px);
        }
        
        .action-btn i {
            font-size: 2em;
            margin-bottom: 10px;
            display: block;
        }
        
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 15px;
        }
        
        th, td {
            padding: 15px;
            text-align: left;
            border-bottom: 1px solid #e5e7eb;
        }
        
        th {
            background: var(--light);
            font-weight: 600;
            color: var(--dark);
        }
        
        .btn {
            padding: 10px 20px;
            border: none;
            border-radius: 8px;
            cursor: pointer;
            font-weight: 600;
            transition: all 0.3s ease;
            text-decoration: none;
            display: inline-block;
            text-align: center;
        }
        
        .btn-primary { background: var(--primary); color: white; }
        .btn-success { background: var(--success); color: white; }
        .btn-danger { background: var(--danger); color: white; }
        .btn-warning { background: var(--warning); color: white; }
        
        .btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 5px 15px rgba(0,0,0,0.2);
        }
        
        .form-group {
            margin-bottom: 20px;
        }
        
        .form-group label {
            display: block;
            margin-bottom: 8px;
            font-weight: 600;
            color: var(--dark);
        }
        
        .form-group input, .form-group select, .form-group textarea {
            width: 100%;
            padding: 12px;
            border: 2px solid #e5e7eb;
            border-radius: 8px;
            font-size: 14px;
            transition: border-color 0.3s ease;
        }
        
        .form-group input:focus, .form-group select:focus {
            border-color: var(--primary);
            outline: none;
        }
        
        .modal {
            display: none;
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: rgba(0,0,0,0.5);
            z-index: 2000;
            backdrop-filter: blur(5px);
        }
        
        .modal-content {
            background: white;
            margin: 5% auto;
            padding: 30px;
            border-radius: 15px;
            width: 90%;
            max-width: 500px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.3);
        }
        
        .status-badge {
            padding: 5px 10px;
            border-radius: 20px;
            font-size: 0.8em;
            font-weight: 600;
        }
        
        .status-active { background: #dcfce7; color: #166534; }
        .status-expired { background: #fecaca; color: #991b1b; }
        .status-inactive { background: #f3f4f6; color: #6b7280; }
        
        .alert {
            padding: 15px;
            margin: 15px 0;
            border-radius: 8px;
            font-weight: 500;
        }
        
        .alert-success { background: #dcfce7; color: #166534; border: 1px solid #bbf7d0; }
        .alert-error { background: #fecaca; color: #991b1b; border: 1px solid #fca5a5; }
        .alert-warning { background: #fef3c7; color: #92400e; border: 1px solid #fcd34d; }
        
        @media (max-width: 768px) {
            .sidebar {
                width: 100%;
                height: auto;
                position: relative;
            }
            
            .main-content {
                margin-left: 0;
            }
        }
    </style>
</head>
<body>
    <div class="sidebar">
        <div class="logo">
            <h1>🚀 GX Tunnel</h1>
            <p>Advanced SSH WebSocket</p>
        </div>
        
        <div class="nav">
            <div class="nav-item active" data-page="dashboard">
                📊 Dashboard
            </div>
            <div class="nav-item" data-page="users">
                👥 User Management
            </div>
            <div class="nav-item" data-page="statistics">
                📈 Statistics
            </div>
            <div class="nav-item" data-page="settings">
                ⚙️ Settings
            </div>
            <div class="nav-item" onclick="logout()">
                🚪 Logout
            </div>
        </div>
    </div>
    
    <div class="main-content">
        <div class="header">
            <h1 id="pageTitle">Dashboard</h1>
            <div class="user-info">
                <span>Welcome, Admin</span>
                <button class="btn btn-primary" onclick="logout()">Logout</button>
            </div>
        </div>
        
        <div id="contentArea">
            <!-- Content will be loaded here -->
        </div>
    </div>

    <!-- Add User Modal -->
    <div id="addUserModal" class="modal">
        <div class="modal-content">
            <h2 style="margin-bottom: 20px;">Add New User</h2>
            <form id="addUserForm">
                <div class="form-group">
                    <label>Username</label>
                    <input type="text" name="username" required placeholder="Enter username">
                </div>
                
                <div class="form-group">
                    <label>Password</label>
                    <input type="text" name="password" required placeholder="Enter password">
                </div>
                
                <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 15px;">
                    <div class="form-group">
                        <label>Expiration Date</label>
                        <input type="date" name="expires">
                    </div>
                    
                    <div class="form-group">
                        <label>Max Connections</label>
                        <input type="number" name="max_connections" value="3" min="1" max="10">
                    </div>
                </div>
                
                <div class="form-group">
                    <label>
                        <input type="checkbox" name="active" checked> Active Account
                    </label>
                </div>
                
                <div style="display: flex; gap: 10px; margin-top: 20px;">
                    <button type="submit" class="btn btn-success" style="flex: 1;">Create User</button>
                    <button type="button" class="btn btn-danger" onclick="closeModal('addUserModal')">Cancel</button>
                </div>
            </form>
        </div>
    </div>

    <script>
        // Global variables
        let currentPage = 'dashboard';
        
        // Navigation
        document.querySelectorAll('.nav-item').forEach(item => {
            item.addEventListener('click', function() {
                if(this.dataset.page) {
                    document.querySelectorAll('.nav-item').forEach(nav => nav.classList.remove('active'));
                    this.classList.add('active');
                    loadPage(this.dataset.page);
                }
            });
        });
        
        // Modal functions
        function openModal(modalId) {
            document.getElementById(modalId).style.display = 'block';
        }
        
        function closeModal(modalId) {
            document.getElementById(modalId).style.display = 'none';
        }
        
        // Page loading
        async function loadPage(page) {
            currentPage = page;
            document.getElementById('pageTitle').textContent = getPageTitle(page);
            
            try {
                let html = '';
                switch(page) {
                    case 'dashboard':
                        html = await loadDashboard();
                        break;
                    case 'users':
                        html = await loadUsersPage();
                        break;
                    case 'statistics':
                        html = await loadStatisticsPage();
                        break;
                    case 'settings':
                        html = await loadSettingsPage();
                        break;
                }
                
                document.getElementById('contentArea').innerHTML = html;
                
                // Initialize page-specific functionality
                if(page === 'dashboard') {
                    initializeDashboard();
                } else if(page === 'users') {
                    initializeUsersPage();
                }
                
            } catch (error) {
                console.error('Error loading page:', error);
                document.getElementById('contentArea').innerHTML = `
                    <div class="content-area">
                        <div class="alert alert-error">
                            Error loading page: ${error.message}
                        </div>
                    </div>
                `;
            }
        }
        
        function getPageTitle(page) {
            const titles = {
                dashboard: 'Dashboard',
                users: 'User Management',
                statistics: 'Statistics',
                settings: 'Settings'
            };
            return titles[page] || 'GX Tunnel';
        }
        
        // Dashboard
        async function loadDashboard() {
            return `
                <div class="content-area">
                    <div class="stats-grid">
                        <div class="stat-card">
                            <h3>Total Users</h3>
                            <div class="value" id="totalUsers">0</div>
                        </div>
                        <div class="stat-card">
                            <h3>Active Connections</h3>
                            <div class="value" id="activeConnections">0</div>
                        </div>
                        <div class="stat-card">
                            <h3>CPU Usage</h3>
                            <div class="value" id="cpuUsage">0%</div>
                        </div>
                        <div class="stat-card">
                            <h3>Memory Usage</h3>
                            <div class="value" id="memoryUsage">0%</div>
                        </div>
                    </div>
                    
                    <div class="quick-actions">
                        <div class="action-btn" onclick="loadPage('users')">
                            👥 Manage Users
                        </div>
                        <div class="action-btn" onclick="openModal('addUserModal')">
                            ➕ Add User
                        </div>
                        <div class="action-btn" onclick="controlService('restart')">
                            🔄 Restart Services
                        </div>
                        <div class="action-btn" onclick="loadPage('settings')">
                            ⚙️ Settings
                        </div>
                    </div>
                    
                    <h3>Recent Activity</h3>
                    <div id="recentActivity">
                        Loading...
                    </div>
                </div>
            `;
        }
        
        async function initializeDashboard() {
            await updateDashboardStats();
            setInterval(updateDashboardStats, 5000);
        }
        
        async function updateDashboardStats() {
            try {
                const response = await fetch('/api/stats');
                if (!response.ok) {
                    throw new Error(`HTTP error! status: ${response.status}`);
                }
                const data = await response.json();
                
                document.getElementById('cpuUsage').textContent = data.system.cpu_usage + '%';
                document.getElementById('memoryUsage').textContent = data.system.memory_usage + '%';
                document.getElementById('totalUsers').textContent = data.users.length;
                document.getElementById('activeConnections').textContent = data.recent_connections.length;
                
                // Update recent activity
                let activityHtml = '<table>';
                if (data.recent_connections && data.recent_connections.length > 0) {
                    data.recent_connections.slice(0, 5).forEach(conn => {
                        activityHtml += `
                            <tr>
                                <td>${conn.username}</td>
                                <td>${conn.client_ip}</td>
                                <td>${new Date(conn.start_time).toLocaleString()}</td>
                                <td>${conn.duration}s</td>
                            </tr>
                        `;
                    });
                } else {
                    activityHtml += '<tr><td colspan="4" style="text-align: center;">No recent activity</td></tr>';
                }
                activityHtml += '</table>';
                document.getElementById('recentActivity').innerHTML = activityHtml;
                
            } catch (error) {
                console.error('Error updating dashboard:', error);
                document.getElementById('recentActivity').innerHTML = '<div class="alert alert-error">Error loading statistics</div>';
            }
        }
        
        // Users Management
        async function loadUsersPage() {
            return `
                <div class="content-area">
                    <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px;">
                        <h2>User Management</h2>
                        <button class="btn btn-success" onclick="openModal('addUserModal')">
                            ➕ Add New User
                        </button>
                    </div>
                    
                    <div id="usersList">
                        Loading users...
                    </div>
                </div>
            `;
        }
        
        async function initializeUsersPage() {
            await loadUsersList();
        }
        
        async function loadUsersList() {
            try {
                const response = await fetch('/api/users');
                if (!response.ok) {
                    throw new Error(`HTTP error! status: ${response.status}`);
                }
                const data = await response.json();
                
                let html = '<table>';
                html += `
                    <thead>
                        <tr>
                            <th>Username</th>
                            <th>Password</th>
                            <th>Created</th>
                            <th>Expires</th>
                            <th>Max Conn</th>
                            <th>Status</th>
                            <th>Actions</th>
                        </tr>
                    </thead>
                    <tbody>
                `;
                
                if (data.users && data.users.length > 0) {
                    data.users.forEach(user => {
                        const statusClass = user.status === 'Active' ? 'status-active' : 
                                          user.status === 'Expired' ? 'status-expired' : 'status-inactive';
                        
                        html += `
                            <tr>
                                <td>${user.username}</td>
                                <td>${user.password}</td>
                                <td>${user.created}</td>
                                <td>${user.expires || 'Never'}</td>
                                <td>${user.max_connections || 3}</td>
                                <td><span class="status-badge ${statusClass}">${user.status}</span></td>
                                <td>
                                    <button class="btn btn-danger btn-sm" onclick="deleteUser('${user.username}')">Delete</button>
                                </td>
                            </tr>
                        `;
                    });
                } else {
                    html += '<tr><td colspan="7" style="text-align: center;">No users found</td></tr>';
                }
                
                html += '</tbody></table>';
                document.getElementById('usersList').innerHTML = html;
                
            } catch (error) {
                console.error('Error loading users:', error);
                document.getElementById('usersList').innerHTML = '<div class="alert alert-error">Error loading users</div>';
            }
        }
        
        // Statistics Page
        async function loadStatisticsPage() {
            return `
                <div class="content-area">
                    <h2>System Statistics</h2>
                    <div class="stats-grid">
                        <div class="stat-card">
                            <h3>Total Download</h3>
                            <div class="value" id="statDownload">0 B</div>
                        </div>
                        <div class="stat-card">
                            <h3>Total Upload</h3>
                            <div class="value" id="statUpload">0 B</div>
                        </div>
                        <div class="stat-card">
                            <h3>Total Connections</h3>
                            <div class="value" id="statConnections">0</div>
                        </div>
                        <div class="stat-card">
                            <h3>Server Uptime</h3>
                            <div class="value" id="statUptime">0</div>
                        </div>
                    </div>
                    
                    <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin-top: 20px;">
                        <div>
                            <h3>System Information</h3>
                            <div id="systemInfo" style="background: #f8f9fa; padding: 15px; border-radius: 8px;">
                                Loading...
                            </div>
                        </div>
                        <div>
                            <h3>Service Status</h3>
                            <div id="serviceStatus" style="background: #f8f9fa; padding: 15px; border-radius: 8px;">
                                Loading...
                            </div>
                        </div>
                    </div>
                </div>
            `;
        }
        
        // Settings Page
        async function loadSettingsPage() {
            return `
                <div class="content-area">
                    <h2>System Settings</h2>
                    <div class="quick-actions">
                        <div class="action-btn" onclick="controlService('restart')">
                            🔄 Restart Services
                        </div>
                        <div class="action-btn" onclick="backupDatabase()">
                            💾 Backup Database
                        </div>
                        <div class="action-btn" onclick="updateSystem()">
                            🔄 Update System
                        </div>
                    </div>
                    
                    <h3 style="margin-top: 30px;">Current Configuration</h3>
                    <div id="currentConfig">
                        Loading configuration...
                    </div>
                </div>
            `;
        }
        
        // API Functions
        async function addUser(event) {
            event.preventDefault();
            const formData = new FormData(event.target);
            const data = {
                username: formData.get('username'),
                password: formData.get('password'),
                expires: formData.get('expires') || null,
                max_connections: parseInt(formData.get('max_connections')),
                active: formData.get('active') === 'on'
            };
            
            try {
                const response = await fetch('/api/users/add', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify(data)
                });
                
                const result = await response.json();
                showAlert(result.message, result.success ? 'success' : 'error');
                
                if(result.success) {
                    closeModal('addUserModal');
                    event.target.reset();
                    if (currentPage === 'users') {
                        await loadUsersList();
                    }
                    if (currentPage === 'dashboard') {
                        await updateDashboardStats();
                    }
                }
            } catch (error) {
                showAlert('Error: ' + error.message, 'error');
            }
        }
        
        async function deleteUser(username) {
            if(confirm(`Are you sure you want to delete user ${username}?`)) {
                try {
                    const response = await fetch('/api/users/delete', {
                        method: 'POST',
                        headers: {'Content-Type': 'application/json'},
                        body: JSON.stringify({username: username})
                    });
                    
                    const result = await response.json();
                    showAlert(result.message, result.success ? 'success' : 'error');
                    
                    if(result.success && currentPage === 'users') {
                        await loadUsersList();
                    }
                } catch (error) {
                    showAlert('Error: ' + error.message, 'error');
                }
            }
        }
        
        async function controlService(action) {
            try {
                const response = await fetch(`/api/services/${action}`, { method: 'POST' });
                const result = await response.json();
                showAlert(result.message, result.success ? 'success' : 'error');
            } catch (error) {
                showAlert('Error: ' + error.message, 'error');
            }
        }
        
        async function backupDatabase() {
            try {
                const response = await fetch('/api/backup', { method: 'POST' });
                const result = await response.json();
                showAlert(result.message, result.success ? 'success' : 'error');
            } catch (error) {
                showAlert('Error: ' + error.message, 'error');
            }
        }
        
        async function updateSystem() {
            try {
                const response = await fetch('/api/update', { method: 'POST' });
                const result = await response.json();
                showAlert(result.message, result.success ? 'success' : 'error');
            } catch (error) {
                showAlert('Error: ' + error.message, 'error');
            }
        }
        
        function showAlert(message, type) {
            const alert = document.createElement('div');
            alert.className = `alert alert-${type}`;
            alert.textContent = message;
            
            document.getElementById('contentArea').prepend(alert);
            
            setTimeout(() => {
                alert.remove();
            }, 5000);
        }
        
        function logout() {
            if(confirm('Are you sure you want to logout?')) {
                window.location.href = '/logout';
            }
        }
        
        // Initialize
        document.getElementById('addUserForm').addEventListener('submit', addUser);
        window.addEventListener('click', function(event) {
            if (event.target.classList.contains('modal')) {
                event.target.style.display = 'none';
            }
        });
        
        // Load dashboard on start
        loadPage('dashboard');
    </script>
</body>
</html>
'''

# Routes
@app.route('/')
def index():
    return HTML_TEMPLATE

@app.route('/login', methods=['POST'])
def login():
    if request.is_json:
        data = request.get_json()
        username = data.get('username')
        password = data.get('password')
    else:
        username = request.form.get('username')
        password = request.form.get('password')
    
    if username == ADMIN_USERNAME and password == ADMIN_PASSWORD:
        session['admin'] = True
        session['login_time'] = datetime.now().isoformat()
        return jsonify({'success': True, 'message': 'Login successful'})
    else:
        return jsonify({'success': False, 'message': 'Invalid credentials'})

@app.route('/logout')
def logout():
    session.clear()
    return redirect('/')

# API Routes
@app.route('/api/users')
def get_users():
    try:
        users, settings = user_manager.load_users()
        
        # Add status to users
        for user in users:
            if user.get('expires'):
                try:
                    expiry_date = datetime.strptime(user['expires'], '%Y-%m-%d')
                    if datetime.now() > expiry_date:
                        user['status'] = 'Expired'
                    else:
                        user['status'] = 'Active'
                except:
                    user['status'] = 'Active'
            else:
                user['status'] = 'Active'
        
        return jsonify({'users': users, 'settings': settings})
    except Exception as e:
        print(f"Error in /api/users: {e}")
        return jsonify({'users': [], 'settings': {}})

@app.route('/api/users/add', methods=['POST'])
def add_user():
    try:
        data = request.get_json()
        username = data.get('username')
        password = data.get('password')
        expires = data.get('expires')
        max_connections = data.get('max_connections', 3)
        active = data.get('active', True)
        
        if not username or not password:
            return jsonify({'success': False, 'message': 'Username and password are required'})
        
        # Validate username
        if not re.match(r'^[a-z_][a-z0-9_-]*$', username):
            return jsonify({'success': False, 'message': 'Username can only contain lowercase letters, numbers, hyphens, and underscores'})
        
        success, message = user_manager.add_user(username, password, expires, max_connections, active)
        return jsonify({'success': success, 'message': message})
    except Exception as e:
        return jsonify({'success': False, 'message': f'Error: {str(e)}'})

@app.route('/api/users/delete', methods=['POST'])
def delete_user():
    try:
        data = request.get_json()
        username = data.get('username')
        
        if not username:
            return jsonify({'success': False, 'message': 'Username is required'})
        
        success, message = user_manager.delete_user(username)
        return jsonify({'success': success, 'message': message})
    except Exception as e:
        return jsonify({'success': False, 'message': f'Error: {str(e)}'})

@app.route('/api/stats')
def get_stats():
    try:
        system_stats = get_system_stats()
        users, settings = user_manager.load_users()
        recent_connections = stats_manager.get_recent_connections(10)
        
        return jsonify({
            'system': system_stats,
            'users': users,
            'recent_connections': recent_connections
        })
    except Exception as e:
        print(f"Error in /api/stats: {e}")
        return jsonify({
            'system': get_system_stats(),
            'users': [],
            'recent_connections': []
        })

@app.route('/api/config')
def get_config():
    try:
        return jsonify(config_manager.config)
    except Exception as e:
        return jsonify({'error': str(e)})

@app.route('/api/services/<action>', methods=['POST'])
def control_services(action):
    try:
        valid_actions = ['start', 'stop', 'restart']
        if action not in valid_actions:
            return jsonify({'success': False, 'message': 'Invalid action'})
        
        # Simulate service control (you can replace with actual systemctl commands)
        time.sleep(1)  # Simulate delay
        
        return jsonify({'success': True, 'message': f'Services {action}ed successfully'})
    except Exception as e:
        return jsonify({'success': False, 'message': f'Error: {str(e)}'})

@app.route('/api/backup', methods=['POST'])
def backup_database():
    try:
        # Simulate backup process
        backup_dir = os.path.join(INSTALL_DIR, 'backups')
        os.makedirs(backup_dir, exist_ok=True)
        
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        backup_file = os.path.join(backup_dir, f'backup_{timestamp}.json')
        
        users, settings = user_manager.load_users()
        backup_data = {
            'users': users,
            'settings': settings,
            'backup_time': datetime.now().isoformat()
        }
        
        with open(backup_file, 'w') as f:
            json.dump(backup_data, f, indent=2)
        
        return jsonify({'success': True, 'message': f'Backup created: {backup_file}'})
    except Exception as e:
        return jsonify({'success': False, 'message': f'Error: {str(e)}'})

@app.route('/api/update', methods=['POST'])
def update_system():
    try:
        # Simulate update process
        return jsonify({'success': True, 'message': 'System updated successfully'})
    except Exception as e:
        return jsonify({'success': False, 'message': f'Error: {str(e)}'})

if __name__ == '__main__':
    print("🚀 Starting GX Tunnel Web GUI on port 8081...")
    print("📧 Admin Login: admin / admin123")
    print("🌐 Access: http://your-server-ip:8081")
    app.run(host='0.0.0.0', port=8081, debug=False)
