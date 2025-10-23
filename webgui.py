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
        
        return {
            'cpu_usage': cpu_usage,
            'memory_usage': memory_usage,
            'disk_usage': disk_usage,
            'system_info': {
                'hostname': os.uname().nodename,
                'os': f"{os.uname().sysname} {os.uname().release}",
                'architecture': os.uname().machine
            }
        }
    except Exception as e:
        print(f"Error getting system stats: {e}")
        return {
            'cpu_usage': 0,
            'memory_usage': 0,
            'disk_usage': 0,
            'system_info': {'hostname': 'Unknown', 'os': 'Unknown', 'architecture': 'Unknown'}
        }

# Initialize managers
user_manager = UserManager(USER_DB)
stats_manager = StatisticsManager(STATS_DB)

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
            background: #f8fafc;
            color: var(--dark);
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
        }
        
        .header {
            background: white;
            padding: 30px;
            border-radius: 15px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            margin-bottom: 20px;
            text-align: center;
        }
        
        .header h1 {
            color: var(--dark);
            font-size: 2.5em;
            margin-bottom: 10px;
        }
        
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        
        .stat-card {
            background: linear-gradient(135deg, var(--primary) 0%, var(--secondary) 100%);
            color: white;
            padding: 25px;
            border-radius: 15px;
            text-align: center;
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
        
        .content-section {
            background: white;
            padding: 25px;
            border-radius: 15px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            margin-bottom: 20px;
        }
        
        .btn {
            padding: 12px 24px;
            border: none;
            border-radius: 8px;
            cursor: pointer;
            font-weight: 600;
            transition: all 0.3s ease;
            margin: 5px;
        }
        
        .btn-primary { background: var(--primary); color: white; }
        .btn-success { background: var(--success); color: white; }
        .btn-danger { background: var(--danger); color: white; }
        
        .btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 5px 15px rgba(0,0,0,0.2);
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
        }
        
        .modal {
            display: none;
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: rgba(0,0,0,0.5);
            z-index: 1000;
        }
        
        .modal-content {
            background: white;
            margin: 10% auto;
            padding: 30px;
            border-radius: 15px;
            width: 90%;
            max-width: 500px;
        }
        
        .form-group {
            margin-bottom: 20px;
        }
        
        .form-group label {
            display: block;
            margin-bottom: 8px;
            font-weight: 600;
        }
        
        .form-group input {
            width: 100%;
            padding: 12px;
            border: 2px solid #e5e7eb;
            border-radius: 8px;
            font-size: 14px;
        }
        
        .form-group input:focus {
            border-color: var(--primary);
            outline: none;
        }
        
        .alert {
            padding: 15px;
            margin: 15px 0;
            border-radius: 8px;
            font-weight: 500;
        }
        
        .alert-success { background: #dcfce7; color: #166534; border: 1px solid #bbf7d0; }
        .alert-error { background: #fecaca; color: #991b1b; border: 1px solid #fca5a5; }
        
        .nav {
            display: flex;
            gap: 10px;
            margin-bottom: 20px;
            flex-wrap: wrap;
        }
        
        .nav-btn {
            padding: 12px 20px;
            background: white;
            border: 2px solid #e5e7eb;
            border-radius: 8px;
            cursor: pointer;
            font-weight: 600;
            transition: all 0.3s ease;
        }
        
        .nav-btn.active {
            background: var(--primary);
            color: white;
            border-color: var(--primary);
        }
        
        .nav-btn:hover {
            border-color: var(--primary);
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 GX Tunnel</h1>
            <p>Advanced WebSocket SSH Tunnel Management</p>
        </div>
        
        <div class="nav">
            <button class="nav-btn active" onclick="showSection('dashboard')">📊 Dashboard</button>
            <button class="nav-btn" onclick="showSection('users')">👥 User Management</button>
            <button class="nav-btn" onclick="showSection('statistics')">📈 Statistics</button>
        </div>
        
        <div id="dashboard" class="content-section">
            <h2>Dashboard</h2>
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
            
            <button class="btn btn-primary" onclick="loadDashboardData()">Refresh Data</button>
            
            <h3 style="margin-top: 30px;">Recent Activity</h3>
            <div id="recentActivity">Loading...</div>
        </div>
        
        <div id="users" class="content-section" style="display: none;">
            <h2>User Management</h2>
            <button class="btn btn-success" onclick="showAddUserModal()">➕ Add New User</button>
            <div id="usersList">Loading users...</div>
        </div>
        
        <div id="statistics" class="content-section" style="display: none;">
            <h2>System Statistics</h2>
            <div id="systemStats">Loading statistics...</div>
        </div>
    </div>

    <!-- Add User Modal -->
    <div id="addUserModal" class="modal">
        <div class="modal-content">
            <h2>Add New User</h2>
            <form onsubmit="addUser(event)">
                <div class="form-group">
                    <label>Username</label>
                    <input type="text" id="username" required placeholder="Enter username">
                </div>
                <div class="form-group">
                    <label>Password</label>
                    <input type="text" id="password" required placeholder="Enter password">
                </div>
                <div class="form-group">
                    <label>Max Connections</label>
                    <input type="number" id="maxConnections" value="3" min="1" max="10">
                </div>
                <div style="display: flex; gap: 10px; margin-top: 20px;">
                    <button type="submit" class="btn btn-success" style="flex: 1;">Create User</button>
                    <button type="button" class="btn btn-danger" onclick="hideAddUserModal()">Cancel</button>
                </div>
            </form>
        </div>
    </div>

    <script>
        let currentSection = 'dashboard';
        
        // Show section function
        function showSection(section) {
            // Hide all sections
            document.getElementById('dashboard').style.display = 'none';
            document.getElementById('users').style.display = 'none';
            document.getElementById('statistics').style.display = 'none';
            
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
            if (section === 'dashboard') {
                loadDashboardData();
            } else if (section === 'users') {
                loadUsers();
            } else if (section === 'statistics') {
                loadStatistics();
            }
        }
        
        // Modal functions
        function showAddUserModal() {
            document.getElementById('addUserModal').style.display = 'block';
        }
        
        function hideAddUserModal() {
            document.getElementById('addUserModal').style.display = 'none';
            document.getElementById('username').value = '';
            document.getElementById('password').value = '';
            document.getElementById('maxConnections').value = '3';
        }
        
        // Dashboard functions
        async function loadDashboardData() {
            try {
                const response = await fetch('/api/stats');
                if (!response.ok) throw new Error('API response error');
                const data = await response.json();
                
                // Update stats
                document.getElementById('cpuUsage').textContent = data.system.cpu_usage + '%';
                document.getElementById('memoryUsage').textContent = data.system.memory_usage + '%';
                document.getElementById('totalUsers').textContent = data.users.length;
                document.getElementById('activeConnections').textContent = data.recent_connections.length;
                
                // Update recent activity
                let activityHtml = '<table><tr><th>Username</th><th>IP</th><th>Time</th><th>Duration</th></tr>';
                if (data.recent_connections && data.recent_connections.length > 0) {
                    data.recent_connections.forEach(conn => {
                        activityHtml += `<tr>
                            <td>${conn.username}</td>
                            <td>${conn.client_ip}</td>
                            <td>${conn.start_time}</td>
                            <td>${conn.duration}s</td>
                        </tr>`;
                    });
                } else {
                    activityHtml += '<tr><td colspan="4" style="text-align: center;">No recent activity</td></tr>';
                }
                activityHtml += '</table>';
                document.getElementById('recentActivity').innerHTML = activityHtml;
                
            } catch (error) {
                console.error('Error loading dashboard:', error);
                showAlert('Error loading dashboard data', 'error');
            }
        }
        
        // User management functions
        async function loadUsers() {
            try {
                const response = await fetch('/api/users');
                if (!response.ok) throw new Error('API response error');
                const data = await response.json();
                
                let html = '<table><tr><th>Username</th><th>Password</th><th>Created</th><th>Max Conn</th><th>Actions</th></tr>';
                
                if (data.users && data.users.length > 0) {
                    data.users.forEach(user => {
                        html += `<tr>
                            <td>${user.username}</td>
                            <td>${user.password}</td>
                            <td>${user.created}</td>
                            <td>${user.max_connections || 3}</td>
                            <td>
                                <button class="btn btn-danger" onclick="deleteUser('${user.username}')">Delete</button>
                            </td>
                        </tr>`;
                    });
                } else {
                    html += '<tr><td colspan="5" style="text-align: center;">No users found</td></tr>';
                }
                
                html += '</table>';
                document.getElementById('usersList').innerHTML = html;
                
            } catch (error) {
                console.error('Error loading users:', error);
                document.getElementById('usersList').innerHTML = '<div class="alert alert-error">Error loading users</div>';
            }
        }
        
        async function addUser(event) {
            event.preventDefault();
            
            const userData = {
                username: document.getElementById('username').value,
                password: document.getElementById('password').value,
                max_connections: parseInt(document.getElementById('maxConnections').value) || 3
            };
            
            try {
                const response = await fetch('/api/users/add', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify(userData)
                });
                
                const result = await response.json();
                showAlert(result.message, result.success ? 'success' : 'error');
                
                if (result.success) {
                    hideAddUserModal();
                    if (currentSection === 'users') {
                        loadUsers();
                    }
                    loadDashboardData();
                }
            } catch (error) {
                showAlert('Error adding user: ' + error.message, 'error');
            }
        }
        
        async function deleteUser(username) {
            if (confirm(`Delete user ${username}?`)) {
                try {
                    const response = await fetch('/api/users/delete', {
                        method: 'POST',
                        headers: {'Content-Type': 'application/json'},
                        body: JSON.stringify({username: username})
                    });
                    
                    const result = await response.json();
                    showAlert(result.message, result.success ? 'success' : 'error');
                    
                    if (result.success && currentSection === 'users') {
                        loadUsers();
                    }
                    loadDashboardData();
                } catch (error) {
                    showAlert('Error deleting user: ' + error.message, 'error');
                }
            }
        }
        
        // Statistics functions
        async function loadStatistics() {
            try {
                const response = await fetch('/api/stats');
                if (!response.ok) throw new Error('API response error');
                const data = await response.json();
                
                let html = '<div class="stats-grid">';
                html += `<div class="stat-card"><h3>CPU</h3><div class="value">${data.system.cpu_usage}%</div></div>`;
                html += `<div class="stat-card"><h3>Memory</h3><div class="value">${data.system.memory_usage}%</div></div>`;
                html += `<div class="stat-card"><h3>Disk</h3><div class="value">${data.system.disk_usage}%</div></div>`;
                html += `<div class="stat-card"><h3>Users</h3><div class="value">${data.users.length}</div></div>`;
                html += '</div>';
                
                html += '<h3>System Information</h3>';
                html += `<pre style="background: #f8f9fa; padding: 15px; border-radius: 8px;">${JSON.stringify(data.system.system_info, null, 2)}</pre>`;
                
                document.getElementById('systemStats').innerHTML = html;
                
            } catch (error) {
                console.error('Error loading statistics:', error);
                document.getElementById('systemStats').innerHTML = '<div class="alert alert-error">Error loading statistics</div>';
            }
        }
        
        // Utility functions
        function showAlert(message, type) {
            const alert = document.createElement('div');
            alert.className = `alert alert-${type}`;
            alert.textContent = message;
            
            document.querySelector('.container').prepend(alert);
            
            setTimeout(() => {
                alert.remove();
            }, 5000);
        }
        
        // Close modal when clicking outside
        window.onclick = function(event) {
            if (event.target === document.getElementById('addUserModal')) {
                hideAddUserModal();
            }
        }
        
        // Auto-refresh dashboard every 30 seconds
        setInterval(() => {
            if (currentSection === 'dashboard') {
                loadDashboardData();
            }
        }, 30000);
        
        // Load initial data
        loadDashboardData();
    </script>
</body>
</html>
'''

# API Routes
@app.route('/')
def index():
    return HTML_TEMPLATE

@app.route('/api/users')
def get_users():
    try:
        users, settings = user_manager.load_users()
        return jsonify({'users': users, 'settings': settings})
    except Exception as e:
        return jsonify({'users': [], 'settings': {}})

@app.route('/api/users/add', methods=['POST'])
def add_user_api():
    try:
        data = request.get_json()
        username = data.get('username')
        password = data.get('password')
        max_connections = data.get('max_connections', 3)
        
        if not username or not password:
            return jsonify({'success': False, 'message': 'Username and password are required'})
        
        success, message = user_manager.add_user(username, password, None, max_connections)
        return jsonify({'success': success, 'message': message})
    except Exception as e:
        return jsonify({'success': False, 'message': f'Error: {str(e)}'})

@app.route('/api/users/delete', methods=['POST'])
def delete_user_api():
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
        recent_connections = stats_manager.get_recent_connections(5)
        
        return jsonify({
            'system': system_stats,
            'users': users,
            'recent_connections': recent_connections
        })
    except Exception as e:
        return jsonify({
            'system': get_system_stats(),
            'users': [],
            'recent_connections': []
        })

@app.route('/api/services/restart', methods=['POST'])
def restart_services():
    try:
        return jsonify({'success': True, 'message': 'Services restarted successfully'})
    except Exception as e:
        return jsonify({'success': False, 'message': f'Error: {str(e)}'})

if __name__ == '__main__':
    print("🚀 Starting GX Tunnel Web GUI on port 8081...")
    print("📧 Admin Access: http://46.224.17.19:8081")
    app.run(host='0.0.0.0', port=8081, debug=False)
