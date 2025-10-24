const express = require('express');
const { spawn, exec } = require('child_process');
const fs = require('fs').promises;
const path = require('path');
const cors = require('cors');

const app = express();
const PORT = 8081;

app.use(cors());
app.use(express.json());
app.use(express.static('public'));

// Configuration
const CONFIG = {
    INSTALL_DIR: '/opt/gx_tunnel',
    USER_DB: '/opt/gx_tunnel/users.json',
    STATS_DB: '/opt/gx_tunnel/statistics.db',
    ADMIN_USERNAME: 'admin',
    ADMIN_PASSWORD: 'admin123'
};

// Utility function to execute shell commands
function executeCommand(command, args = []) {
    return new Promise((resolve, reject) => {
        const child = spawn(command, args);
        let stdout = '';
        let stderr = '';

        child.stdout.on('data', (data) => {
            stdout += data.toString();
        });

        child.stderr.on('data', (data) => {
            stderr += data.toString();
        });

        child.on('close', (code) => {
            if (code === 0) {
                resolve(stdout.trim());
            } else {
                reject(new Error(stderr || `Command failed with code ${code}`));
            }
        });

        child.on('error', (error) => {
            reject(error);
        });
    });
}

// Execute bash script
function executeBashScript(scriptPath, args = []) {
    return executeCommand('bash', [scriptPath, ...args]);
}

// Execute Python script
function executePythonScript(scriptPath, args = []) {
    return executeCommand('python3', [scriptPath, ...args]);
}

// Read JSON file
async function readJSONFile(filePath) {
    try {
        const data = await fs.readFile(filePath, 'utf8');
        return JSON.parse(data);
    } catch (error) {
        console.error(`Error reading ${filePath}:`, error);
        return { users: [], settings: {} };
    }
}

// Write JSON file
async function writeJSONFile(filePath, data) {
    try {
        await fs.writeFile(filePath, JSON.stringify(data, null, 2));
        return true;
    } catch (error) {
        console.error(`Error writing ${filePath}:`, error);
        return false;
    }
}

// Get system statistics using bash commands
async function getSystemStats() {
    try {
        const cpuUsage = await executeCommand('sh', ['-c', "top -bn1 | grep 'Cpu(s)' | awk '{print $2}' | cut -d'%' -f1"]);
        const memoryInfo = await executeCommand('sh', ['-c', "free | awk 'NR==2{printf \"%.2f\", $3*100/$2}'"]);
        const diskUsage = await executeCommand('sh', ['-c', "df -h / | awk 'NR==2{print $5}' | cut -d'%' -f1"]);
        const uptime = await executeCommand('uptime', ['-p']);
        const hostname = await executeCommand('hostname');
        
        // Get active connections
        const activeConnections = await executeCommand('sh', ['-c', "ss -tun | wc -l"]).then(val => parseInt(val) - 1);

        return {
            cpu_usage: parseFloat(cpuUsage) || 0,
            memory_usage: parseFloat(memoryInfo) || 0,
            disk_usage: parseFloat(diskUsage) || 0,
            active_connections: activeConnections || 0,
            system_info: {
                hostname: hostname || 'Unknown',
                os: await getOSInfo(),
                architecture: await executeCommand('uname', ['-m']),
                uptime: uptime || 'Unknown'
            }
        };
    } catch (error) {
        console.error('Error getting system stats:', error);
        return getFallbackStats();
    }
}

// Get OS information
async function getOSInfo() {
    try {
        const osRelease = await executeCommand('sh', ['-c', "cat /etc/os-release | grep PRETTY_NAME | cut -d'=' -f2 | tr -d '\"'"]);;
        return osRelease || 'Linux';
    } catch (error) {
        return 'Linux';
    }
}

// Fallback stats
function getFallbackStats() {
    return {
        cpu_usage: 0,
        memory_usage: 0,
        disk_usage: 0,
        active_connections: 0,
        system_info: {
            hostname: 'Unknown',
            os: 'Linux',
            architecture: 'Unknown',
            uptime: 'Unknown'
        }
    };
}

// Get recent connections from SQLite
async function getRecentConnections(limit = 10) {
    try {
        const query = `SELECT username, client_ip, start_time, duration, download_bytes, upload_bytes 
                      FROM connection_log 
                      ORDER BY id DESC 
                      LIMIT ${limit}`;
        
        const result = await executeCommand('sqlite3', [CONFIG.STATS_DB, query]);
        
        if (!result) return [];
        
        return result.split('\n').filter(line => line.trim()).map(line => {
            const [username, client_ip, start_time, duration, download_bytes, upload_bytes] = line.split('|');
            return {
                username: username || 'Unknown',
                client_ip: client_ip || 'Unknown',
                start_time: start_time || 'Unknown',
                duration: parseInt(duration) || 0,
                download_bytes: parseInt(download_bytes) || 0,
                upload_bytes: parseInt(upload_bytes) || 0
            };
        });
    } catch (error) {
        console.error('Error getting recent connections:', error);
        return [];
    }
}

// Routes

// Serve main page
app.get('/', (req, res) => {
    res.send(`
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
            
            <div id="alertContainer"></div>
            
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
                <div id="recentActivity">Loading...</div>
            </div>
            
            <div id="users" class="content-section" style="display: none;">
                <h2>👥 User Management</h2>
                <button class="btn btn-success" onclick="showAddUserModal()">➕ Add New User</button>
                <div id="usersList">Loading users...</div>
            </div>
            
            <div id="statistics" class="content-section" style="display: none;">
                <h2>📈 System Statistics</h2>
                <div id="systemStats">Loading statistics...</div>
            </div>
            
            <div id="system" class="content-section" style="display: none;">
                <h2>⚙️ System Information</h2>
                <div id="systemInfo">Loading system information...</div>
            </div>
        </div>

        <div id="addUserModal" class="modal">
            <div class="modal-content">
                <h2>➕ Add New User</h2>
                <form onsubmit="addUser(event)">
                    <div class="form-group">
                        <label>👤 Username</label>
                        <input type="text" id="username" required placeholder="Enter username">
                    </div>
                    <div class="form-group">
                        <label>🔑 Password</label>
                        <input type="text" id="password" required placeholder="Enter password">
                    </div>
                    <div class="form-group">
                        <label>🔗 Max Connections</label>
                        <input type="number" id="maxConnections" value="3" min="1" max="10">
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
            
            function showSection(section) {
                document.querySelectorAll('.content-section').forEach(el => el.style.display = 'none');
                document.querySelectorAll('.nav-btn').forEach(btn => btn.classList.remove('active'));
                
                document.getElementById(section).style.display = 'block';
                event.target.classList.add('active');
                currentSection = section;
                loadAllData();
            }
            
            function showAddUserModal() {
                document.getElementById('addUserModal').style.display = 'block';
            }
            
            function hideAddUserModal() {
                document.getElementById('addUserModal').style.display = 'none';
                document.getElementById('username').value = '';
                document.getElementById('password').value = '';
                document.getElementById('maxConnections').value = '3';
            }
            
            async function loadAllData() {
                try {
                    const response = await fetch('/api/all-data');
                    const data = await response.json();
                    
                    updateDashboard(data);
                    updateUsers(data);
                    updateStatistics(data);
                    updateSystemInfo(data);
                    updateLastUpdate();
                    
                } catch (error) {
                    showAlert('Error loading data: ' + error.message, 'error');
                }
            }
            
            function updateDashboard(data) {
                document.getElementById('cpuUsage').textContent = data.system_stats.cpu_usage + '%';
                document.getElementById('memoryUsage').textContent = data.system_stats.memory_usage + '%';
                document.getElementById('totalUsers').textContent = data.users.length;
                document.getElementById('activeConnections').textContent = data.system_stats.active_connections;
                
                let activityHtml = '<table><tr><th>Username</th><th>IP</th><th>Start Time</th><th>Duration</th><th>Download</th><th>Upload</th></tr>';
                
                if (data.recent_connections.length > 0) {
                    data.recent_connections.forEach(conn => {
                        const downloadMB = (conn.download_bytes / (1024 * 1024)).toFixed(2);
                        const uploadMB = (conn.upload_bytes / (1024 * 1024)).toFixed(2);
                        
                        activityHtml += '<tr>' +
                            '<td>' + (conn.username || 'N/A') + '</td>' +
                            '<td>' + (conn.client_ip || 'N/A') + '</td>' +
                            '<td>' + (conn.start_time || 'N/A') + '</td>' +
                            '<td>' + (conn.duration || 0) + 's</td>' +
                            '<td>' + downloadMB + ' MB</td>' +
                            '<td>' + uploadMB + ' MB</td>' +
                        '</tr>';
                    });
                } else {
                    activityHtml += '<tr><td colspan="6" style="text-align: center; padding: 40px;">No recent activity</td></tr>';
                }
                activityHtml += '</table>';
                document.getElementById('recentActivity').innerHTML = activityHtml;
            }
            
            function updateUsers(data) {
                let html = '<table><tr><th>Username</th><th>Password</th><th>Created</th><th>Max Connections</th><th>Actions</th></tr>';
                
                if (data.users.length > 0) {
                    data.users.forEach(user => {
                        html += '<tr>' +
                            '<td>' + user.username + '</td>' +
                            '<td>' + user.password + '</td>' +
                            '<td>' + user.created + '</td>' +
                            '<td>' + (user.max_connections || 3) + '</td>' +
                            '<td><button class="btn btn-danger" onclick="deleteUser(\\'' + user.username + '\\')">🗑️ Delete</button></td>' +
                        '</tr>';
                    });
                } else {
                    html += '<tr><td colspan="5" style="text-align: center; padding: 40px;">No users found</td></tr>';
                }
                
                html += '</table>';
                document.getElementById('usersList').innerHTML = html;
            }
            
            function updateStatistics(data) {
                let html = '<div class="stats-grid">';
                html += '<div class="stat-card"><h3>CPU Usage</h3><div class="value">' + data.system_stats.cpu_usage + '%</div></div>';
                html += '<div class="stat-card"><h3>Memory Usage</h3><div class="value">' + data.system_stats.memory_usage + '%</div></div>';
                html += '<div class="stat-card"><h3>Disk Usage</h3><div class="value">' + data.system_stats.disk_usage + '%</div></div>';
                html += '<div class="stat-card"><h3>Total Users</h3><div class="value">' + data.users.length + '</div></div>';
                html += '</div>';
                document.getElementById('systemStats').innerHTML = html;
            }
            
            function updateSystemInfo(data) {
                const sysInfo = data.system_stats.system_info;
                let info = 'Hostname: ' + sysInfo.hostname + '\\n';
                info += 'OS: ' + sysInfo.os + '\\n';
                info += 'Architecture: ' + sysInfo.architecture + '\\n';
                info += 'Uptime: ' + sysInfo.uptime + '\\n';
                info += 'CPU Usage: ' + data.system_stats.cpu_usage + '%\\n';
                info += 'Memory Usage: ' + data.system_stats.memory_usage + '%\\n';
                info += 'Active Connections: ' + data.system_stats.active_connections;
                
                document.getElementById('systemInfo').innerHTML = 
                    '<div style="background: #f8f9fa; padding: 25px; border-radius: 12px;">' +
                    '<pre style="white-space: pre-wrap; font-family: monospace;">' + info + '</pre>' +
                    '</div>';
            }
            
            function updateLastUpdate() {
                document.getElementById('lastUpdate').textContent = 'Last update: ' + new Date().toLocaleTimeString();
            }
            
            async function addUser(event) {
                event.preventDefault();
                
                const userData = {
                    username: document.getElementById('username').value,
                    password: document.getElementById('password').value,
                    max_connections: parseInt(document.getElementById('maxConnections').value) || 3
                };
                
                try {
                    const response = await fetch('/api/users', {
                        method: 'POST',
                        headers: {'Content-Type': 'application/json'},
                        body: JSON.stringify(userData)
                    });
                    
                    const result = await response.json();
                    showAlert(result.message, result.success ? 'success' : 'error');
                    
                    if (result.success) {
                        hideAddUserModal();
                        loadAllData();
                    }
                } catch (error) {
                    showAlert('Error adding user: ' + error.message, 'error');
                }
            }
            
            async function deleteUser(username) {
                if (confirm('Delete user ' + username + '?')) {
                    try {
                        const response = await fetch('/api/users/' + encodeURIComponent(username), {
                            method: 'DELETE'
                        });
                        
                        const result = await response.json();
                        showAlert(result.message, result.success ? 'success' : 'error');
                        
                        if (result.success) {
                            loadAllData();
                        }
                    } catch (error) {
                        showAlert('Error deleting user: ' + error.message, 'error');
                    }
                }
            }
            
            function showAlert(message, type) {
                const alert = document.createElement('div');
                alert.className = 'alert alert-' + type;
                alert.textContent = message;
                document.getElementById('alertContainer').appendChild(alert);
                
                setTimeout(() => alert.remove(), 5000);
            }
            
            // Auto-refresh every 10 seconds
            setInterval(loadAllData, 10000);
            
            // Initial load
            loadAllData();
        </script>
    </body>
    </html>
    `);
});

// API Routes

// Get all data
app.get('/api/all-data', async (req, res) => {
    try {
        const [systemStats, usersData, recentConnections] = await Promise.all([
            getSystemStats(),
            readJSONFile(CONFIG.USER_DB),
            getRecentConnections()
        ]);

        res.json({
            system_stats: systemStats,
            users: usersData.users || [],
            recent_connections: recentConnections
        });
    } catch (error) {
        console.error('Error in /api/all-data:', error);
        res.status(500).json({
            system_stats: getFallbackStats(),
            users: [],
            recent_connections: [],
            error: error.message
        });
    }
});

// Add user
app.post('/api/users', async (req, res) => {
    try {
        const { username, password, max_connections = 3 } = req.body;
        
        if (!username || !password) {
            return res.json({ success: false, message: 'Username and password are required' });
        }

        // Read current users
        const usersData = await readJSONFile(CONFIG.USER_DB);
        const users = usersData.users || [];

        // Check if user exists
        if (users.find(u => u.username === username)) {
            return res.json({ success: false, message: 'User already exists' });
        }

        // Add new user
        const newUser = {
            username,
            password,
            created: new Date().toISOString().split('T')[0],
            max_connections: parseInt(max_connections),
            active: true
        };

        users.push(newUser);
        usersData.users = users;

        // Save to file
        const saved = await writeJSONFile(CONFIG.USER_DB, usersData);
        
        if (saved) {
            res.json({ success: true, message: 'User created successfully' });
        } else {
            res.json({ success: false, message: 'Failed to save user' });
        }

    } catch (error) {
        console.error('Error adding user:', error);
        res.json({ success: false, message: 'Error: ' + error.message });
    }
});

// Delete user
app.delete('/api/users/:username', async (req, res) => {
    try {
        const username = req.params.username;
        
        // Read current users
        const usersData = await readJSONFile(CONFIG.USER_DB);
        const users = usersData.users || [];

        // Filter out the user to delete
        const filteredUsers = users.filter(u => u.username !== username);
        
        if (filteredUsers.length === users.length) {
            return res.json({ success: false, message: 'User not found' });
        }

        usersData.users = filteredUsers;

        // Save to file
        const saved = await writeJSONFile(CONFIG.USER_DB, usersData);
        
        if (saved) {
            res.json({ success: true, message: 'User deleted successfully' });
        } else {
            res.json({ success: false, message: 'Failed to delete user' });
        }

    } catch (error) {
        console.error('Error deleting user:', error);
        res.json({ success: false, message: 'Error: ' + error.message });
    }
});

// Get system stats
app.get('/api/system-stats', async (req, res) => {
    try {
        const stats = await getSystemStats();
        res.json(stats);
    } catch (error) {
        res.status(500).json(getFallbackStats());
    }
});

// Start server
app.listen(PORT, '0.0.0.0', () => {
    console.log('🚀 GX Tunnel Web GUI started');
    console.log('📊 Dashboard: http://localhost:' + PORT);
    console.log('🌐 Network: http://' + getNetworkAddress() + ':' + PORT);
});

// Get network address
function getNetworkAddress() {
    const { networkInterfaces } = require('os');
    const nets = networkInterfaces();
    
    for (const name of Object.keys(nets)) {
        for (const net of nets[name]) {
            if (net.family === 'IPv4' && !net.internal) {
                return net.address;
            }
        }
    }
    return 'localhost';
}
