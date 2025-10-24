#!/usr/bin/python3
from flask import Flask, request, jsonify, session, redirect, url_for, render_template_string
from flask_cors import CORS
import json
import sqlite3
import subprocess
import psutil
import os
import re
from datetime import datetime, timedelta
import secrets
import threading
import time

app = Flask(__name__)
app.secret_key = secrets.token_hex(32)
CORS(app)

# Configuration
USER_DB = "/opt/gx_tunnel/users.json"
STATS_DB = "/opt/gx_tunnel/statistics.db"
CONFIG_FILE = "/opt/gx_tunnel/config.json"
INSTALL_DIR = "/opt/gx_tunnel"

# Admin credentials
ADMIN_USERNAME = "admin"
ADMIN_PASSWORD = "admin123"

# Global data storage (instead of API calls)
global_data = {
    'system_stats': {},
    'users': [],
    'recent_connections': [],
    'last_update': 0
}

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
            return []

def get_system_stats():
    try:
        cpu_usage = psutil.cpu_percent(interval=1)
        memory = psutil.virtual_memory()
        memory_usage = memory.percent
        disk = psutil.disk_usage('/')
        disk_usage = disk.percent
        
        # Get network stats
        net_io = psutil.net_io_counters()
        
        # Get active connections count
        try:
            result = subprocess.run(['ss', '-tun'], capture_output=True, text=True)
            active_connections = len(result.stdout.strip().split('\n')) - 1
        except:
            active_connections = 0
        
        return {
            'cpu_usage': round(cpu_usage, 1),
            'memory_usage': round(memory_usage, 1),
            'disk_usage': round(disk_usage, 1),
            'active_connections': active_connections,
            'network_sent': net_io.bytes_sent,
            'network_recv': net_io.bytes_recv,
            'system_info': {
                'hostname': os.uname().nodename,
                'os': f"{os.uname().sysname} {os.uname().release}",
                'architecture': os.uname().machine,
                'uptime': get_system_uptime()
            }
        }
    except Exception as e:
        print(f"Error getting system stats: {e}")
        return {
            'cpu_usage': 0,
            'memory_usage': 0,
            'disk_usage': 0,
            'active_connections': 0,
            'network_sent': 0,
            'network_recv': 0,
            'system_info': {'hostname': 'Unknown', 'os': 'Unknown', 'architecture': 'Unknown', 'uptime': 'Unknown'}
        }

def get_system_uptime():
    try:
        with open('/proc/uptime', 'r') as f:
            uptime_seconds = float(f.readline().split()[0])
        
        days = int(uptime_seconds // 86400)
        hours = int((uptime_seconds % 86400) // 3600)
        minutes = int((uptime_seconds % 3600) // 60)
        
        if days > 0:
            return f"{days}d {hours}h {minutes}m"
        elif hours > 0:
            return f"{hours}h {minutes}m"
        else:
            return f"{minutes}m"
    except:
        return "Unknown"

def update_global_data():
    """Update global data in background"""
    while True:
        try:
            global_data['system_stats'] = get_system_stats()
            global_data['users'], _ = user_manager.load_users()
            global_data['recent_connections'] = stats_manager.get_recent_connections(10)
            global_data['last_update'] = time.time()
        except Exception as e:
            print(f"Error updating global data: {e}")
        
        time.sleep(5)  # Update every 5 seconds

# Initialize managers
user_manager = UserManager(USER_DB)
stats_manager = StatisticsManager(STATS_DB)

# Start background data updater
data_updater_thread = threading.Thread(target=update_global_data, daemon=True)
data_updater_thread.start()

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
        }
        
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
        }
        
        body {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            color: var(--dark);
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
        }
        
        .header {
            background: rgba(255, 255, 255, 0.95);
            padding: 30px;
            border-radius: 20px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
            margin-bottom: 25px;
            text-align: center;
            backdrop-filter: blur(10px);
        }
        
        .header h1 {
            background: linear-gradient(135deg, var(--primary), var(--secondary));
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            font-size: 3em;
            margin-bottom: 10px;
            font-weight: 800;
        }
        
        .header p {
            color: #6b7280;
            font-size: 1.2em;
        }
        
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
            gap: 25px;
            margin-bottom: 30px;
        }
        
        .stat-card {
            background: rgba(255, 255, 255, 0.95);
            padding: 30px;
            border-radius: 20px;
            text-align: center;
            box-shadow: 0 5px 20px rgba(0,0,0,0.1);
            backdrop-filter: blur(10px);
            border: 1px solid rgba(255, 255, 255, 0.2);
            transition: transform 0.3s ease, box-shadow 0.3s ease;
        }
        
        .stat-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 15px 35px rgba(0,0,0,0.2);
        }
        
        .stat-card h3 {
            font-size: 0.9em;
            color: #6b7280;
            margin-bottom: 15px;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        
        .stat-card .value {
            font-size: 2.5em;
            font-weight: 800;
            background: linear-gradient(135deg, var(--primary), var(--secondary));
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        
        .content-section {
            background: rgba(255, 255, 255, 0.95);
            padding: 30px;
            border-radius: 20px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.1);
            margin-bottom: 25px;
            backdrop-filter: blur(10px);
            border: 1px solid rgba(255, 255, 255, 0.2);
        }
        
        .btn {
            padding: 15px 30px;
            border: none;
            border-radius: 12px;
            cursor: pointer;
            font-weight: 700;
            transition: all 0.3s ease;
            margin: 5px;
            font-size: 14px;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        
        .btn-primary { 
            background: linear-gradient(135deg, var(--primary), var(--secondary));
            color: white;
            box-shadow: 0 5px 15px rgba(102, 126, 234, 0.4);
        }
        
        .btn-success { 
            background: linear-gradient(135deg, var(--success), #059669);
            color: white;
            box-shadow: 0 5px 15px rgba(16, 185, 129, 0.4);
        }
        
        .btn-danger { 
            background: linear-gradient(135deg, var(--danger), #dc2626);
            color: white;
            box-shadow: 0 5px 15px rgba(239, 68, 68, 0.4);
        }
        
        .btn:hover {
            transform: translateY(-3px);
            box-shadow: 0 10px 25px rgba(0,0,0,0.3);
        }
        
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 20px;
            background: white;
            border-radius: 12px;
            overflow: hidden;
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
        }
        
        th, td {
            padding: 18px;
            text-align: left;
            border-bottom: 1px solid #e5e7eb;
        }
        
        th {
            background: linear-gradient(135deg, var(--primary), var(--secondary));
            color: white;
            font-weight: 700;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        
        tr:hover {
            background-color: #f8fafc;
        }
        
        .modal {
            display: none;
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: rgba(0,0,0,0.7);
            z-index: 1000;
            backdrop-filter: blur(5px);
        }
        
        .modal-content {
            background: white;
            margin: 10% auto;
            padding: 40px;
            border-radius: 20px;
            width: 90%;
            max-width: 500px;
            box-shadow: 0 25px 50px rgba(0,0,0,0.3);
            animation: modalSlideIn 0.3s ease;
        }
        
        @keyframes modalSlideIn {
            from { transform: translateY(-50px); opacity: 0; }
            to { transform: translateY(0); opacity: 1; }
        }
        
        .form-group {
            margin-bottom: 25px;
        }
        
        .form-group label {
            display: block;
            margin-bottom: 10px;
            font-weight: 700;
            color: var(--dark);
        }
        
        .form-group input {
            width: 100%;
            padding: 15px;
            border: 2px solid #e5e7eb;
            border-radius: 12px;
            font-size: 16px;
            transition: border-color 0.3s ease;
        }
        
        .form-group input:focus {
            border-color: var(--primary);
            outline: none;
            box-shadow: 0 0 0 3px rgba(102, 126, 234, 0.1);
        }
        
        .alert {
            padding: 20px;
            margin: 20px 0;
            border-radius: 12px;
            font-weight: 600;
            animation: alertSlideIn 0.3s ease;
        }
        
        @keyframes alertSlideIn {
            from { transform: translateX(-100px); opacity: 0; }
            to { transform: translateX(0); opacity: 1; }
        }
        
        .alert-success { 
            background: linear-gradient(135deg, #dcfce7, #bbf7d0);
            color: #166534;
            border: 1px solid #bbf7d0;
        }
        
        .alert-error { 
            background: linear-gradient(135deg, #fecaca, #fca5a5);
            color: #991b1b;
            border: 1px solid #fca5a5;
        }
        
        .nav {
            display: flex;
            gap: 15px;
            margin-bottom: 25px;
            flex-wrap: wrap;
        }
        
        .nav-btn {
            padding: 15px 25px;
            background: rgba(255, 255, 255, 0.9);
            border: 2px solid rgba(255, 255, 255, 0.3);
            border-radius: 12px;
            cursor: pointer;
            font-weight: 700;
            transition: all 0.3s ease;
            backdrop-filter: blur(10px);
            color: var(--dark);
        }
        
        .nav-btn.active {
            background: linear-gradient(135deg, var(--primary), var(--secondary));
            color: white;
            border-color: transparent;
            box-shadow: 0 5px 15px rgba(102, 126, 234, 0.4);
        }
        
        .nav-btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 8px 20px rgba(0,0,0,0.2);
        }
        
        .last-update {
            text-align: center;
            color: #9ca3af;
            font-size: 0.9em;
            margin-top: 20px;
        }
        
        .user-count {
            font-size: 0.8em;
            color: #6b7280;
            margin-top: 10px;
        }
        
        .connection-status {
            display: inline-block;
            width: 10px;
            height: 10px;
            border-radius: 50%;
            margin-right: 8px;
        }
        
        .status-online { background-color: var(--success); }
        .status-offline { background-color: var(--danger); }
        
        @media (max-width: 768px) {
            .container {
                padding: 10px;
            }
            
            .header h1 {
                font-size: 2em;
            }
            
            .stats-grid {
                grid-template-columns: 1fr;
            }
            
            .nav {
                flex-direction: column;
            }
            
            .nav-btn {
                text-align: center;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 GX Tunnel</h1>
            <p>Advanced WebSocket SSH Tunnel Management</p>
            <div class="last-update" id="lastUpdate">Last update: Just now</div>
        </div>
        
        <div class="nav">
            <button class="nav-btn active" onclick="showSection('dashboard')">📊 Dashboard</button>
            <button class="nav-btn" onclick="showSection('users')">👥 User Management</button>
            <button class="nav-btn" onclick="showSection('statistics')">📈 Statistics</button>
            <button class="nav-btn" onclick="showSection('system')">⚙️ System Info</button>
        </div>
        
        <!-- Alert Container -->
        <div id="alertContainer"></div>
        
        <!-- Dashboard Section -->
        <div id="dashboard" class="content-section">
            <h2>📊 Dashboard Overview</h2>
            <div class="stats-grid">
                <div class="stat-card">
                    <h3>CPU Usage</h3>
                    <div class="value" id="cpuUsage">0%</div>
                </div>
                <div class="stat-card">
                    <h3>Memory Usage</h3>
                    <div class="value" id="memoryUsage">0%</div>
                </div>
                <div class="stat-card">
                    <h3>Total Users</h3>
                    <div class="value" id="totalUsers">0</div>
                </div>
                <div class="stat-card">
                    <h3>Active Connections</h3>
                    <div class="value" id="activeConnections">0</div>
                </div>
            </div>
            
            <button class="btn btn-primary" onclick="loadAllData()">🔄 Refresh Data</button>
            
            <h3 style="margin-top: 40px; margin-bottom: 20px;">🕒 Recent Activity</h3>
            <div id="recentActivity">
                <table>
                    <tr><th>Username</th><th>IP Address</th><th>Start Time</th><th>Duration</th><th>Download</th><th>Upload</th></tr>
                    <tr><td colspan="6" style="text-align: center; padding: 40px;">Loading recent activity...</td></tr>
                </table>
            </div>
        </div>
        
        <!-- User Management Section -->
        <div id="users" class="content-section" style="display: none;">
            <h2>👥 User Management</h2>
            <button class="btn btn-success" onclick="showAddUserModal()">➕ Add New User</button>
            <div class="user-count" id="userCount">Loading users...</div>
            <div id="usersList">
                <table>
                    <tr><th>Username</th><th>Password</th><th>Created</th><th>Max Connections</th><th>Actions</th></tr>
                    <tr><td colspan="5" style="text-align: center; padding: 40px;">Loading users...</td></tr>
                </table>
            </div>
        </div>
        
        <!-- Statistics Section -->
        <div id="statistics" class="content-section" style="display: none;">
            <h2>📈 System Statistics</h2>
            <div id="systemStats">
                <div class="stats-grid">
                    <div class="stat-card"><h3>CPU</h3><div class="value">0%</div></div>
                    <div class="stat-card"><h3>Memory</h3><div class="value">0%</div></div>
                    <div class="stat-card"><h3>Disk</h3><div class="value">0%</div></div>
                    <div class="stat-card"><h3>Users</h3><div class="value">0</div></div>
                </div>
            </div>
        </div>
        
        <!-- System Info Section -->
        <div id="system" class="content-section" style="display: none;">
            <h2>⚙️ System Information</h2>
            <div id="systemInfo">
                <div style="background: #f8f9fa; padding: 25px; border-radius: 12px; margin-top: 20px;">
                    <pre style="white-space: pre-wrap; font-family: 'Courier New', monospace;">Loading system information...</pre>
                </div>
            </div>
        </div>
    </div>

    <!-- Add User Modal -->
    <div id="addUserModal" class="modal">
        <div class="modal-content">
            <h2 style="margin-bottom: 25px;">➕ Add New User</h2>
            <form onsubmit="addUser(event)">
                <div class="form-group">
                    <label>👤 Username</label>
                    <input type="text" id="username" required placeholder="Enter username (letters, numbers, hyphens)" pattern="[a-zA-Z0-9_-]+" title="Only letters, numbers, hyphens and underscores allowed">
                </div>
                <div class="form-group">
                    <label>🔑 Password</label>
                    <input type="text" id="password" required placeholder="Enter password" minlength="3">
                </div>
                <div class="form-group">
                    <label>🔗 Max Connections</label>
                    <input type="number" id="maxConnections" value="3" min="1" max="10" placeholder="Maximum simultaneous connections">
                </div>
                <div class="form-group">
                    <label>📅 Expiration Date (Optional)</label>
                    <input type="date" id="expiryDate" placeholder="YYYY-MM-DD">
                </div>
                <div style="display: flex; gap: 15px; margin-top: 30px;">
                    <button type="submit" class="btn btn-success" style="flex: 1;">✅ Create User</button>
                    <button type="button" class="btn btn-danger" onclick="hideAddUserModal()">❌ Cancel</button>
                </div>
            </form>
        </div>
    </div>

    <script>
        let currentSection = 'dashboard';
        let autoRefresh = true;
        
        // Show section function
        function showSection(section) {
            // Hide all sections
            document.getElementById('dashboard').style.display = 'none';
            document.getElementById('users').style.display = 'none';
            document.getElementById('statistics').style.display = 'none';
            document.getElementById('system').style.display = 'none';
            
            // Remove active class from all buttons
            document.querySelectorAll('.nav-btn').forEach(btn => {
                btn.classList.remove('active');
            });
            
            // Show selected section
            document.getElementById(section).style.display = 'block';
            
            // Add active class to clicked button
            event.target.classList.add('active');
            
            currentSection = section;
            
            // Load data for the section
            loadAllData();
        }
        
        // Modal functions
        function showAddUserModal() {
            document.getElementById('addUserModal').style.display = 'block';
            document.getElementById('username').focus();
        }
        
        function hideAddUserModal() {
            document.getElementById('addUserModal').style.display = 'none';
            document.getElementById('username').value = '';
            document.getElementById('password').value = '';
            document.getElementById('maxConnections').value = '3';
            document.getElementById('expiryDate').value = '';
        }
        
        // Data loading functions
        async function loadAllData() {
            try {
                // Get all data from the server
                const response = await fetch('/get_all_data');
                if (!response.ok) throw new Error('Failed to fetch data');
                const data = await response.json();
                
                updateDashboard(data);
                updateUsers(data);
                updateStatistics(data);
                updateSystemInfo(data);
                updateLastUpdate();
                
            } catch (error) {
                console.error('Error loading data:', error);
                showAlert('Error loading data: ' + error.message, 'error');
            }
        }
        
        function updateDashboard(data) {
            if (currentSection !== 'dashboard') return;
            
            // Update stats cards
            document.getElementById('cpuUsage').textContent = data.system_stats.cpu_usage + '%';
            document.getElementById('memoryUsage').textContent = data.system_stats.memory_usage + '%';
            document.getElementById('totalUsers').textContent = data.users.length;
            document.getElementById('activeConnections').textContent = data.system_stats.active_connections;
            
            // Update recent activity
            let activityHtml = '<table><tr><th>Username</th><th>IP</th><th>Start Time</th><th>Duration</th><th>Download</th><th>Upload</th></tr>';
            
            if (data.recent_connections && data.recent_connections.length > 0) {
                data.recent_connections.forEach(conn => {
                    const downloadMB = (conn.download_bytes / (1024 * 1024)).toFixed(2);
                    const uploadMB = (conn.upload_bytes / (1024 * 1024)).toFixed(2);
                    
                    activityHtml += `<tr>
                        <td>${conn.username || 'N/A'}</td>
                        <td>${conn.client_ip || 'N/A'}</td>
                        <td>${conn.start_time || 'N/A'}</td>
                        <td>${conn.duration || 0}s</td>
                        <td>${downloadMB} MB</td>
                        <td>${uploadMB} MB</td>
                    </tr>`;
                });
            } else {
                activityHtml += '<tr><td colspan="6" style="text-align: center; padding: 40px; color: #6b7280;">No recent activity</td></tr>';
            }
            activityHtml += '</table>';
            document.getElementById('recentActivity').innerHTML = activityHtml;
        }
        
        function updateUsers(data) {
            if (currentSection !== 'users') return;
            
            // Update user count
            document.getElementById('userCount').textContent = `Total users: ${data.users.length}`;
            
            // Update users list
            let html = '<table><tr><th>Username</th><th>Password</th><th>Created</th><th>Max Connections</th><th>Status</th><th>Actions</th></tr>';
            
            if (data.users && data.users.length > 0) {
                data.users.forEach(user => {
                    const isExpired = user.expires && new Date(user.expires) < new Date();
                    const status = isExpired ? '❌ Expired' : '✅ Active';
                    const statusClass = isExpired ? 'status-offline' : 'status-online';
                    
                    html += `<tr>
                        <td>${user.username}</td>
                        <td>${user.password}</td>
                        <td>${user.created}</td>
                        <td>${user.max_connections || 3}</td>
                        <td><span class="connection-status ${statusClass}"></span>${status}</td>
                        <td>
                            <button class="btn btn-danger" onclick="deleteUser('${user.username}')">🗑️ Delete</button>
                        </td>
                    </tr>`;
                });
            } else {
                html += '<tr><td colspan="6" style="text-align: center; padding: 40px; color: #6b7280;">No users found</td></tr>';
            }
            
            html += '</table>';
            document.getElementById('usersList').innerHTML = html;
        }
        
        function updateStatistics(data) {
            if (currentSection !== 'statistics') return;
            
            let html = '<div class="stats-grid">';
            html += `<div class="stat-card"><h3>CPU Usage</h3><div class="value">${data.system_stats.cpu_usage}%</div></div>`;
            html += `<div class="stat-card"><h3>Memory Usage</h3><div class="value">${data.system_stats.memory_usage}%</div></div>`;
            html += `<div class="stat-card"><h3>Disk Usage</h3><div class="value">${data.system_stats.disk_usage}%</div></div>`;
            html += `<div class="stat-card"><h3>Total Users</h3><div class="value">${data.users.length}</div></div>`;
            html += `<div class="stat-card"><h3>Active Connections</h3><div class="value">${data.system_stats.active_connections}</div></div>`;
            html += `<div class="stat-card"><h3>Network Sent</h3><div class="value">${(data.system_stats.network_sent / (1024 * 1024)).toFixed(1)}MB</div></div>`;
            html += '</div>';
            
            document.getElementById('systemStats').innerHTML = html;
        }
        
        function updateSystemInfo(data) {
            if (currentSection !== 'system') return;
            
            const systemInfo = data.system_stats.system_info;
            let infoHtml = '<div style="background: #f8f9fa; padding: 25px; border-radius: 12px;">';
            infoHtml += '<pre style="white-space: pre-wrap; font-family: \'Courier New\', monospace; line-height: 1.6;">';
            infoHtml += `Hostname:       ${systemInfo.hostname}\n`;
            infoHtml += `Operating System: ${systemInfo.os}\n`;
            infoHtml += `Architecture:   ${systemInfo.architecture}\n`;
            infoHtml += `Uptime:         ${systemInfo.uptime}\n`;
            infoHtml += `CPU Usage:      ${data.system_stats.cpu_usage}%\n`;
            infoHtml += `Memory Usage:   ${data.system_stats.memory_usage}%\n`;
            infoHtml += `Disk Usage:     ${data.system_stats.disk_usage}%\n`;
            infoHtml += `Active Connections: ${data.system_stats.active_connections}\n`;
            infoHtml += `Total Users:    ${data.users.length}\n`;
            infoHtml += '</pre></div>';
            
            document.getElementById('systemInfo').innerHTML = infoHtml;
        }
        
        function updateLastUpdate() {
            const now = new Date();
            document.getElementById('lastUpdate').textContent = 
                `Last update: ${now.toLocaleTimeString()}`;
        }
        
        // User management functions
        async function addUser(event) {
            event.preventDefault();
            
            const userData = {
                username: document.getElementById('username').value,
                password: document.getElementById('password').value,
                max_connections: parseInt(document.getElementById('maxConnections').value) || 3,
                expires: document.getElementById('expiryDate').value || null
            };
            
            // Basic validation
            if (!userData.username || !userData.password) {
                showAlert('Username and password are required', 'error');
                return;
            }
            
            if (!/^[a-zA-Z0-9_-]+$/.test(userData.username)) {
                showAlert('Username can only contain letters, numbers, hyphens, and underscores', 'error');
                return;
            }
            
            try {
                const response = await fetch('/add_user', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify(userData)
                });
                
                const result = await response.json();
                showAlert(result.message, result.success ? 'success' : 'error');
                
                if (result.success) {
                    hideAddUserModal();
                    loadAllData(); // Reload all data
                }
            } catch (error) {
                showAlert('Error adding user: ' + error.message, 'error');
            }
        }
        
        async function deleteUser(username) {
            if (confirm(`Are you sure you want to delete user "${username}"?`)) {
                try {
                    const response = await fetch('/delete_user', {
                        method: 'POST',
                        headers: {'Content-Type': 'application/json'},
                        body: JSON.stringify({username: username})
                    });
                    
                    const result = await response.json();
                    showAlert(result.message, result.success ? 'success' : 'error');
                    
                    if (result.success) {
                        loadAllData(); // Reload all data
                    }
                } catch (error) {
                    showAlert('Error deleting user: ' + error.message, 'error');
                }
            }
        }
        
        // Utility functions
        function showAlert(message, type) {
            const alertContainer = document.getElementById('alertContainer');
            const alert = document.createElement('div');
            alert.className = `alert alert-${type}`;
            alert.textContent = message;
            
            alertContainer.appendChild(alert);
            
            setTimeout(() => {
                alert.remove();
            }, 5000);
        }
        
        // Close modal when clicking outside
        window.onclick = function(event) {
            const modal = document.getElementById('addUserModal');
            if (event.target === modal) {
                hideAddUserModal();
            }
        }
        
        // Auto-refresh data every 10 seconds
        setInterval(() => {
            if (autoRefresh) {
                loadAllData();
            }
        }, 10000);
        
        // Initial load
        document.addEventListener('DOMContentLoaded', function() {
            loadAllData();
        });
    </script>
</body>
</html>
'''

@app.route('/')
def index():
    return render_template_string(HTML_TEMPLATE)

@app.route('/get_all_data')
def get_all_data():
    """Get all data in one endpoint to avoid multiple API calls"""
    try:
        return jsonify({
            'system_stats': global_data['system_stats'],
            'users': global_data['users'],
            'recent_connections': global_data['recent_connections'],
            'last_update': global_data['last_update']
        })
    except Exception as e:
        return jsonify({
            'system_stats': get_system_stats(),
            'users': [],
            'recent_connections': [],
            'last_update': time.time(),
            'error': str(e)
        })

@app.route('/add_user', methods=['POST'])
def add_user():
    try:
        data = request.get_json()
        username = data.get('username')
        password = data.get('password')
        max_connections = data.get('max_connections', 3)
        expires = data.get('expires')
        
        if not username or not password:
            return jsonify({'success': False, 'message': 'Username and password are required'})
        
        success, message = user_manager.add_user(username, password, expires, max_connections)
        return jsonify({'success': success, 'message': message})
        
    except Exception as e:
        return jsonify({'success': False, 'message': f'Error: {str(e)}'})

@app.route('/delete_user', methods=['POST'])
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

@app.route('/get_stats')
def get_stats():
    """Get system statistics"""
    try:
        return jsonify(get_system_stats())
    except Exception as e:
        return jsonify({'error': str(e)})

if __name__ == '__main__':
    print("🚀 Starting GX Tunnel Web GUI...")
    print("📊 Dashboard available at: http://localhost:5000")
    print("🔧 Press Ctrl+C to stop the server")
    
    # Ensure directories exist
    os.makedirs(os.path.dirname(USER_DB), exist_ok=True)
    os.makedirs(os.path.dirname(STATS_DB), exist_ok=True)
    
    app.run(host='0.0.0.0', port=5000, debug=False)
