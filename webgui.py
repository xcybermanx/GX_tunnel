#!/usr/bin/python3
from flask import Flask, request, jsonify, session, redirect, url_for
from flask_cors import CORS
import json
import sqlite3
import subprocess
import psutil
import os
from datetime import datetime, timedelta

app = Flask(__name__)
app.secret_key = 'gx_tunnel_secret_key_2024'
CORS(app)

# Configuration
USER_DB = "/opt/gx_tunnel/users.json"
STATS_DB = "/opt/gx_tunnel/statistics.db"
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
        except:
            return [], {}
    
    def save_users(self, users, settings):
        data = {
            'users': users,
            'settings': settings
        }
        with open(self.db_path, 'w') as f:
            json.dump(data, f, indent=2)
    
    def add_user(self, username, password, expires=None, max_connections=3):
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
            'active': True
        }
        
        users.append(user_data)
        self.save_users(users, settings)
        
        # Create system user
        try:
            subprocess.run(['useradd', '-m', '-s', '/usr/sbin/nologin', username], check=True, capture_output=True)
            subprocess.run(['chpasswd'], input=f"{username}:{password}", text=True, check=True, capture_output=True)
        except subprocess.CalledProcessError as e:
            return False, f"Failed to create system user: {str(e)}"
        
        return True, "User created successfully"
    
    def delete_user(self, username):
        users, settings = self.load_users()
        users = [u for u in users if u['username'] != username]
        self.save_users(users, settings)
        
        # Delete system user
        try:
            subprocess.run(['userdel', '-r', username], check=True, capture_output=True)
        except subprocess.CalledProcessError:
            pass  # User might not exist in system
        
        return True, "User deleted successfully"

class StatisticsManager:
    def __init__(self, db_path):
        self.db_path = db_path
    
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
        except:
            pass
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
        except:
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
        except:
            return []

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
        
        return {
            'cpu_usage': cpu_usage,
            'memory_usage': memory_usage,
            'memory_total': round(memory_total, 2),
            'memory_used': round(memory_used, 2),
            'disk_usage': disk_usage,
            'disk_total': round(disk_total, 2),
            'disk_used': round(disk_used, 2),
            'network': network_stats,
            'uptime': str(uptime).split('.')[0]
        }
    except Exception as e:
        print(f"Error getting system stats: {e}")
        return {
            'cpu_usage': 0,
            'memory_usage': 0,
            'memory_total': 0,
            'memory_used': 0,
            'disk_usage': 0,
            'disk_total': 0,
            'disk_used': 0,
            'network': {'bytes_sent': 0, 'bytes_recv': 0},
            'uptime': 'Unknown'
        }

def bytes_to_human(bytes_size):
    if bytes_size == 0:
        return "0 B"
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if bytes_size < 1024.0:
            return f"{bytes_size:.2f} {unit}"
        bytes_size /= 1024.0
    return f"{bytes_size:.2f} PB"

# Routes
@app.route('/')
def index():
    if 'admin' not in session:
        return redirect(url_for('login'))
    
    return '''
<!DOCTYPE html>
<html>
<head>
    <title>GX Tunnel - Administration</title>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: #f5f6fa;
            color: #333;
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 20px;
            text-align: center;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
        }
        .nav {
            background: white;
            padding: 15px;
            border-radius: 10px;
            margin-bottom: 20px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .nav button {
            padding: 10px 20px;
            margin: 0 5px;
            border: none;
            border-radius: 5px;
            cursor: pointer;
            background: #667eea;
            color: white;
        }
        .nav button:hover {
            background: #5a6fd8;
        }
        .content {
            background: white;
            padding: 20px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin-bottom: 20px;
        }
        .stat-card {
            background: #f8f9fa;
            padding: 15px;
            border-radius: 8px;
            text-align: center;
        }
        .stat-card h3 {
            color: #666;
            font-size: 14px;
            margin-bottom: 8px;
        }
        .stat-card .value {
            font-size: 24px;
            font-weight: bold;
            color: #333;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 15px;
        }
        th, td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #ddd;
        }
        th {
            background: #f8f9fa;
            font-weight: 600;
        }
        .btn {
            padding: 8px 16px;
            border: none;
            border-radius: 4px;
            cursor: pointer;
            margin: 2px;
        }
        .btn-primary { background: #667eea; color: white; }
        .btn-success { background: #28a745; color: white; }
        .btn-danger { background: #dc3545; color: white; }
        .btn-warning { background: #ffc107; color: black; }
        .form-group { margin-bottom: 15px; }
        .form-group label { display: block; margin-bottom: 5px; font-weight: 500; }
        .form-group input, .form-group select {
            width: 100%;
            padding: 8px;
            border: 1px solid #ddd;
            border-radius: 4px;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>🚀 GX Tunnel - Web Administration</h1>
        <p>Advanced WebSocket SSH Tunnel Management</p>
    </div>
    
    <div class="container">
        <div class="nav">
            <button onclick="showSection('dashboard')">📊 Dashboard</button>
            <button onclick="showSection('users')">👥 User Management</button>
            <button onclick="showSection('stats')">📈 Statistics</button>
            <button onclick="logout()">🚪 Logout</button>
        </div>
        
        <div class="content" id="contentArea">
            <div id="dashboard">
                <h2>Dashboard</h2>
                <div class="stats-grid" id="dashboardStats">
                    <!-- Stats will be loaded here -->
                </div>
                <div>
                    <h3>Quick Actions</h3>
                    <button class="btn btn-success" onclick="controlService('start')">Start Services</button>
                    <button class="btn btn-warning" onclick="controlService('restart')">Restart Services</button>
                    <button class="btn btn-danger" onclick="controlService('stop')">Stop Services</button>
                    <button class="btn btn-primary" onclick="showSection('users')">Manage Users</button>
                </div>
            </div>
            
            <div id="users" style="display: none;">
                <h2>User Management</h2>
                <button class="btn btn-success" onclick="showAddUserForm()">Add New User</button>
                
                <div id="addUserForm" style="display: none; background: #f8f9fa; padding: 20px; border-radius: 8px; margin: 15px 0;">
                    <h3>Add New User</h3>
                    <form onsubmit="addUser(event)">
                        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 15px;">
                            <div class="form-group">
                                <label>Username:</label>
                                <input type="text" name="username" required>
                            </div>
                            <div class="form-group">
                                <label>Password:</label>
                                <input type="text" name="password" required>
                            </div>
                        </div>
                        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 15px;">
                            <div class="form-group">
                                <label>Expiration Date:</label>
                                <input type="date" name="expires">
                            </div>
                            <div class="form-group">
                                <label>Max Connections:</label>
                                <input type="number" name="max_connections" value="3" min="1">
                            </div>
                        </div>
                        <button type="submit" class="btn btn-success">Create User</button>
                        <button type="button" class="btn btn-danger" onclick="hideAddUserForm()">Cancel</button>
                    </form>
                </div>
                
                <div id="usersList">
                    <table>
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
                        <tbody id="usersTable">
                            <!-- Users will be loaded here -->
                        </tbody>
                    </table>
                </div>
            </div>
            
            <div id="stats" style="display: none;">
                <h2>System Statistics</h2>
                <div class="stats-grid">
                    <div class="stat-card">
                        <h3>Total Download</h3>
                        <div class="value" id="totalDownload">0 B</div>
                    </div>
                    <div class="stat-card">
                        <h3>Total Upload</h3>
                        <div class="value" id="totalUpload">0 B</div>
                    </div>
                    <div class="stat-card">
                        <h3>Total Connections</h3>
                        <div class="value" id="totalConnections">0</div>
                    </div>
                    <div class="stat-card">
                        <h3>Server Uptime</h3>
                        <div class="value" id="serverUptime">0</div>
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
                
                <div style="margin-top: 20px;">
                    <h3>Recent Connections</h3>
                    <div id="recentConnections">
                        Loading...
                    </div>
                </div>
            </div>
        </div>
    </div>

    <script>
        // Navigation
        function showSection(section) {
            document.querySelectorAll('#contentArea > div').forEach(div => {
                div.style.display = 'none';
            });
            document.getElementById(section).style.display = 'block';
            
            if(section === 'dashboard') {
                loadDashboard();
            } else if(section === 'users') {
                loadUsers();
            } else if(section === 'stats') {
                loadStatistics();
            }
        }
        
        // Dashboard functions
        async function loadDashboard() {
            await loadStats();
        }
        
        async function loadStats() {
            try {
                const response = await fetch('/api/stats');
                const data = await response.json();
                
                // Update dashboard stats
                document.getElementById('dashboardStats').innerHTML = `
                    <div class="stat-card">
                        <h3>CPU Usage</h3>
                        <div class="value">${data.system.cpu_usage}%</div>
                    </div>
                    <div class="stat-card">
                        <h3>Memory Usage</h3>
                        <div class="value">${data.system.memory_usage}%</div>
                    </div>
                    <div class="stat-card">
                        <h3>Active Services</h3>
                        <div class="value">${Object.values(data.services).filter(s => s === 'active').length}/2</div>
                    </div>
                    <div class="stat-card">
                        <h3>Total Users</h3>
                        <div class="value" id="totalUsers">Loading...</div>
                    </div>
                `;
                
                // Load users count
                const usersResponse = await fetch('/api/users');
                const usersData = await usersResponse.json();
                document.getElementById('totalUsers').textContent = usersData.users.length;
                
            } catch (error) {
                console.error('Error loading stats:', error);
                document.getElementById('dashboardStats').innerHTML = '<p>Error loading dashboard data</p>';
            }
        }
        
        // User management functions
        async function loadUsers() {
            try {
                const response = await fetch('/api/users');
                const data = await response.json();
                displayUsers(data.users);
            } catch (error) {
                console.error('Error loading users:', error);
                document.getElementById('usersTable').innerHTML = '<tr><td colspan="7">Error loading users</td></tr>';
            }
        }
        
        function displayUsers(users) {
            const tbody = document.getElementById('usersTable');
            tbody.innerHTML = '';
            
            if (users.length === 0) {
                tbody.innerHTML = '<tr><td colspan="7">No users found</td></tr>';
                return;
            }
            
            users.forEach(user => {
                const row = document.createElement('tr');
                row.innerHTML = `
                    <td>${user.username}</td>
                    <td>${user.password}</td>
                    <td>${user.created}</td>
                    <td>${user.expires || 'Never'}</td>
                    <td>${user.max_connections || 3}</td>
                    <td>${user.status || 'Active'}</td>
                    <td>
                        <button class="btn btn-danger btn-sm" onclick="deleteUser('${user.username}')">Delete</button>
                    </td>
                `;
                tbody.appendChild(row);
            });
        }
        
        function showAddUserForm() {
            document.getElementById('addUserForm').style.display = 'block';
        }
        
        function hideAddUserForm() {
            document.getElementById('addUserForm').style.display = 'none';
        }
        
        async function addUser(event) {
            event.preventDefault();
            
            const formData = new FormData(event.target);
            const data = {
                username: formData.get('username'),
                password: formData.get('password'),
                expires: formData.get('expires') || null,
                max_connections: parseInt(formData.get('max_connections'))
            };
            
            try {
                const response = await fetch('/api/users/add', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify(data)
                });
                
                const result = await response.json();
                alert(result.message);
                
                if(result.success) {
                    hideAddUserForm();
                    event.target.reset();
                    loadUsers();
                }
            } catch (error) {
                alert('Error: ' + error.message);
            }
        }
        
        async function deleteUser(username) {
            if(confirm(`Are you sure you want to delete user ${username}?`)) {
                try {
                    const response = await fetch('/api/users/delete', {
                        method: 'POST',
                        headers: {
                            'Content-Type': 'application/json',
                        },
                        body: JSON.stringify({username: username})
                    });
                    
                    const result = await response.json();
                    alert(result.message);
                    
                    if(result.success) {
                        loadUsers();
                    }
                } catch (error) {
                    alert('Error: ' + error.message);
                }
            }
        }
        
        // Statistics functions
        async function loadStatistics() {
            try {
                const response = await fetch('/api/stats');
                const data = await response.json();
                updateStatistics(data);
            } catch (error) {
                console.error('Error loading statistics:', error);
            }
        }
        
        function updateStatistics(data) {
            // Update global stats
            document.getElementById('totalDownload').textContent = formatBytes(data.global.total_download || 0);
            document.getElementById('totalUpload').textContent = formatBytes(data.global.total_upload || 0);
            document.getElementById('totalConnections').textContent = data.global.total_connections || 0;
            document.getElementById('serverUptime').textContent = data.system.uptime;
            
            // Update system info
            document.getElementById('systemInfo').innerHTML = `
                <p><strong>CPU Usage:</strong> ${data.system.cpu_usage}%</p>
                <p><strong>Memory:</strong> ${data.system.memory_used}GB / ${data.system.memory_total}GB (${data.system.memory_usage}%)</p>
                <p><strong>Disk:</strong> ${data.system.disk_used}GB / ${data.system.disk_total}GB (${data.system.disk_usage}%)</p>
                <p><strong>Network Sent:</strong> ${formatBytes(data.system.network.bytes_sent)}</p>
                <p><strong>Network Received:</strong> ${formatBytes(data.system.network.bytes_recv)}</p>
            `;
            
            // Update service status
            document.getElementById('serviceStatus').innerHTML = `
                <p><strong>Tunnel Service:</strong> <span style="color: ${data.services.tunnel === 'active' ? 'green' : 'red'}">${data.services.tunnel}</span></p>
                <p><strong>Web GUI:</strong> <span style="color: ${data.services.webgui === 'active' ? 'green' : 'red'}">${data.services.webgui}</span></p>
            `;
            
            // Update recent connections
            let connectionsHtml = '<table><thead><tr><th>User</th><th>IP</th><th>Time</th><th>Duration</th><th>Download</th><th>Upload</th></tr></thead><tbody>';
            
            if (data.recent_connections && data.recent_connections.length > 0) {
                data.recent_connections.forEach(conn => {
                    connectionsHtml += `
                        <tr>
                            <td>${conn.username}</td>
                            <td>${conn.client_ip}</td>
                            <td>${new Date(conn.start_time).toLocaleString()}</td>
                            <td>${conn.duration}s</td>
                            <td>${formatBytes(conn.download_bytes)}</td>
                            <td>${formatBytes(conn.upload_bytes)}</td>
                        </tr>
                    `;
                });
            } else {
                connectionsHtml += '<tr><td colspan="6">No recent connections</td></tr>';
            }
            
            connectionsHtml += '</tbody></table>';
            document.getElementById('recentConnections').innerHTML = connectionsHtml;
        }
        
        // Service control
        async function controlService(action) {
            try {
                const response = await fetch(`/api/services/${action}`, { method: 'POST' });
                const result = await response.json();
                alert(result.message);
                loadStats();
            } catch (error) {
                alert('Error: ' + error.message);
            }
        }
        
        // Utility functions
        function formatBytes(bytes) {
            if (bytes === 0) return '0 B';
            const k = 1024;
            const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
            const i = Math.floor(Math.log(bytes) / Math.log(k));
            return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
        }
        
        function logout() {
            window.location.href = '/logout';
        }
        
        // Initialize dashboard on load
        showSection('dashboard');
        setInterval(loadStats, 10000); // Refresh every 10 seconds
    </script>
</body>
</html>
'''

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        username = request.form.get('username')
        password = request.form.get('password')
        
        if username == ADMIN_USERNAME and password == ADMIN_PASSWORD:
            session['admin'] = True
            return jsonify({'success': True, 'message': 'Login successful'})
        else:
            return jsonify({'success': False, 'message': 'Invalid credentials'})
    
    return '''
    <!DOCTYPE html>
    <html>
    <head>
        <title>GX Tunnel - Login</title>
        <style>
            body { 
                font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                height: 100vh;
                display: flex;
                align-items: center;
                justify-content: center;
                margin: 0;
            }
            .login-container {
                background: white;
                padding: 40px;
                border-radius: 10px;
                box-shadow: 0 15px 35px rgba(0,0,0,0.1);
                width: 100%;
                max-width: 400px;
            }
            .logo { text-align: center; margin-bottom: 30px; }
            .logo h1 { color: #333; margin-bottom: 5px; }
            .logo p { color: #666; }
            .form-group { margin-bottom: 20px; }
            .form-group label { display: block; margin-bottom: 5px; color: #333; }
            .form-group input {
                width: 100%;
                padding: 12px;
                border: 2px solid #ddd;
                border-radius: 5px;
                font-size: 16px;
            }
            .btn {
                width: 100%;
                padding: 12px;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white;
                border: none;
                border-radius: 5px;
                font-size: 16px;
                cursor: pointer;
            }
            .alert {
                padding: 10px;
                margin-bottom: 20px;
                border-radius: 5px;
                display: none;
            }
            .alert.error { background: #fee; border: 1px solid #fcc; color: #c66; }
        </style>
    </head>
    <body>
        <div class="login-container">
            <div class="logo">
                <h1>🚀 GX Tunnel</h1>
                <p>Web Administration Login</p>
            </div>
            <div id="alert" class="alert error"></div>
            <form onsubmit="login(event)">
                <div class="form-group">
                    <label>Username:</label>
                    <input type="text" name="username" value="admin" required>
                </div>
                <div class="form-group">
                    <label>Password:</label>
                    <input type="password" name="password" value="admin123" required>
                </div>
                <button type="submit" class="btn">Login</button>
            </form>
        </div>
        <script>
            async function login(event) {
                event.preventDefault();
                const formData = new FormData(event.target);
                const data = {
                    username: formData.get('username'),
                    password: formData.get('password')
                };
                
                try {
                    const response = await fetch('/login', {
                        method: 'POST',
                        headers: {'Content-Type': 'application/json'},
                        body: JSON.stringify(data)
                    });
                    
                    const result = await response.json();
                    if (result.success) {
                        window.location.href = '/';
                    } else {
                        showAlert(result.message, 'error');
                    }
                } catch (error) {
                    showAlert('Login failed: ' + error.message, 'error');
                }
            }
            
            function showAlert(message, type) {
                const alert = document.getElementById('alert');
                alert.textContent = message;
                alert.className = `alert ${type}`;
                alert.style.display = 'block';
            }
        </script>
    </body>
    </html>
    '''

@app.route('/logout')
def logout():
    session.pop('admin', None)
    return redirect(url_for('login'))

# API Routes
@app.route('/api/users')
def get_users():
    if 'admin' not in session:
        return jsonify({'error': 'Unauthorized'}), 401
    
    user_manager = UserManager(USER_DB)
    users, settings = user_manager.load_users()
    stats_manager = StatisticsManager(STATS_DB)
    
    # Add statistics to users
    for user in users:
        user_stats = stats_manager.get_user_stats(user['username'])
        if user_stats:
            user.update(user_stats)
        else:
            user.update({
                'connections': 0,
                'download_bytes': 0,
                'upload_bytes': 0,
                'last_connection': 'Never'
            })
        
        # Check if account is expired
        if user.get('expires'):
            try:
                expiry_date = datetime.strptime(user['expires'], '%Y-%m-%d')
                if datetime.now() > expiry_date:
                    user['status'] = 'Expired'
                else:
                    days_left = (expiry_date - datetime.now()).days
                    user['status'] = f'{days_left} days left'
            except:
                user['status'] = 'Active'
        else:
            user['status'] = 'Active'
    
    return jsonify({'users': users, 'settings': settings})

@app.route('/api/users/add', methods=['POST'])
def add_user():
    if 'admin' not in session:
        return jsonify({'success': False, 'message': 'Unauthorized'}), 401
    
    data = request.get_json()
    username = data.get('username')
    password = data.get('password')
    expires = data.get('expires')
    max_connections = data.get('max_connections', 3)
    
    if not username or not password:
        return jsonify({'success': False, 'message': 'Username and password are required'})
    
    user_manager = UserManager(USER_DB)
    success, message = user_manager.add_user(username, password, expires, max_connections)
    
    return jsonify({'success': success, 'message': message})

@app.route('/api/users/delete', methods=['POST'])
def delete_user():
    if 'admin' not in session:
        return jsonify({'success': False, 'message': 'Unauthorized'}), 401
    
    data = request.get_json()
    username = data.get('username')
    
    if not username:
        return jsonify({'success': False, 'message': 'Username is required'})
    
    user_manager = UserManager(USER_DB)
    success, message = user_manager.delete_user(username)
    
    return jsonify({'success': success, 'message': message})

@app.route('/api/stats')
def get_stats():
    if 'admin' not in session:
        return jsonify({'error': 'Unauthorized'}), 401
    
    stats_manager = StatisticsManager(STATS_DB)
    system_stats = get_system_stats()
    global_stats = stats_manager.get_global_stats()
    recent_connections = stats_manager.get_recent_connections(10)
    
    # Get service status
    try:
        tunnel_status = subprocess.run(['systemctl', 'is-active', 'gx-tunnel'], 
                                     capture_output=True, text=True).stdout.strip()
        webgui_status = subprocess.run(['systemctl', 'is-active', 'gx-webgui'], 
                                     capture_output=True, text=True).stdout.strip()
    except:
        tunnel_status = 'unknown'
        webgui_status = 'unknown'
    
    return jsonify({
        'system': system_stats,
        'global': global_stats,
        'recent_connections': recent_connections,
        'services': {
            'tunnel': tunnel_status,
            'webgui': webgui_status
        }
    })

@app.route('/api/services/restart', methods=['POST'])
def restart_services():
    if 'admin' not in session:
        return jsonify({'success': False, 'message': 'Unauthorized'}), 401
    
    try:
        subprocess.run(['systemctl', 'restart', 'gx-tunnel'], check=True, capture_output=True)
        subprocess.run(['systemctl', 'restart', 'gx-webgui'], check=True, capture_output=True)
        return jsonify({'success': True, 'message': 'Services restarted successfully'})
    except subprocess.CalledProcessError as e:
        return jsonify({'success': False, 'message': f'Failed to restart services: {str(e)}'})

@app.route('/api/services/stop', methods=['POST'])
def stop_services():
    if 'admin' not in session:
        return jsonify({'success': False, 'message': 'Unauthorized'}), 401
    
    try:
        subprocess.run(['systemctl', 'stop', 'gx-tunnel'], check=True, capture_output=True)
        subprocess.run(['systemctl', 'stop', 'gx-webgui'], check=True, capture_output=True)
        return jsonify({'success': True, 'message': 'Services stopped successfully'})
    except subprocess.CalledProcessError as e:
        return jsonify({'success': False, 'message': f'Failed to stop services: {str(e)}'})

@app.route('/api/services/start', methods=['POST'])
def start_services():
    if 'admin' not in session:
        return jsonify({'success': False, 'message': 'Unauthorized'}), 401
    
    try:
        subprocess.run(['systemctl', 'start', 'gx-tunnel'], check=True, capture_output=True)
        subprocess.run(['systemctl', 'start', 'gx-webgui'], check=True, capture_output=True)
        return jsonify({'success': True, 'message': 'Services started successfully'})
    except subprocess.CalledProcessError as e:
        return jsonify({'success': False, 'message': f'Failed to start services: {str(e)}'})

if __name__ == '__main__':
    print("🚀 Starting GX Tunnel Web GUI on port 8081...")
    app.run(host='0.0.0.0', port=8081, debug=False)
