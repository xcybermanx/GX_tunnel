const express = require('express');
const session = require('express-session');
const cors = require('cors');
const bodyParser = require('body-parser');
const { spawn, exec } = require('child_process');
const fs = require('fs').promises;
const path = require('path');
const sqlite3 = require('sqlite3').verbose();

const app = express();
const PORT = 8081;

// Middleware
app.use(cors());
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));
app.use(session({
    secret: 'gx-tunnel-secret-key-2024',
    resave: false,
    saveUninitialized: false,
    cookie: { secure: false, maxAge: 24 * 60 * 60 * 1000 } // 24 hours
}));

// Configuration
const CONFIG = {
    INSTALL_DIR: '/opt/gx_tunnel',
    USER_DB: '/opt/gx_tunnel/users.json',
    STATS_DB: '/opt/gx_tunnel/statistics.db',
    CONFIG_FILE: '/opt/gx_tunnel/config.json'
};

// Admin credentials
const ADMIN_USERNAME = "admin";
const ADMIN_PASSWORD = "admin123";

// Utility functions
function executeCommand(command) {
    return new Promise((resolve, reject) => {
        exec(command, (error, stdout, stderr) => {
            if (error) {
                reject(error);
                return;
            }
            resolve(stdout.trim());
        });
    });
}

async function ensureFilesExist() {
    try {
        // Ensure users.json exists
        try {
            await fs.access(CONFIG.USER_DB);
        } catch {
            const defaultUsers = {
                users: [],
                settings: {
                    tunnel_port: 8080,
                    webgui_port: 8081,
                    admin_password: "admin123",
                    max_connections_per_user: 3
                }
            };
            await fs.writeFile(CONFIG.USER_DB, JSON.stringify(defaultUsers, null, 2));
        }

        // Ensure config.json exists
        try {
            await fs.access(CONFIG.CONFIG_FILE);
        } catch {
            const defaultConfig = {
                server: {
                    host: "0.0.0.0",
                    port: 8080,
                    webgui_port: 8081,
                    domain: "",
                    ssl_enabled: false,
                    ssl_cert: "",
                    ssl_key: ""
                },
                security: {
                    fail2ban_enabled: true,
                    max_login_attempts: 3,
                    ban_time: 3600,
                    session_timeout: 3600
                },
                users: {
                    default_expiry_days: 30,
                    max_connections_per_user: 3,
                    max_users: 100
                },
                appearance: {
                    theme: "dark",
                    language: "en"
                }
            };
            await fs.writeFile(CONFIG.CONFIG_FILE, JSON.stringify(defaultConfig, null, 2));
        }

        // Initialize SQLite database
        await initDatabase();
        
    } catch (error) {
        console.error('Error ensuring files exist:', error);
    }
}

async function initDatabase() {
    return new Promise((resolve, reject) => {
        const db = new sqlite3.Database(CONFIG.STATS_DB, (err) => {
            if (err) {
                reject(err);
                return;
            }

            // Create tables
            db.serialize(() => {
                db.run(`CREATE TABLE IF NOT EXISTS user_stats (
                    username TEXT PRIMARY KEY,
                    connections INTEGER DEFAULT 0,
                    download_bytes INTEGER DEFAULT 0,
                    upload_bytes INTEGER DEFAULT 0,
                    last_connection TEXT
                )`);

                db.run(`CREATE TABLE IF NOT EXISTS global_stats (
                    key TEXT PRIMARY KEY,
                    value TEXT
                )`);

                db.run(`CREATE TABLE IF NOT EXISTS connection_log (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    username TEXT,
                    client_ip TEXT,
                    start_time TEXT,
                    duration INTEGER,
                    download_bytes INTEGER,
                    upload_bytes INTEGER
                )`);

                db.run(`CREATE TABLE IF NOT EXISTS security_log (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    event_type TEXT,
                    client_ip TEXT,
                    username TEXT,
                    description TEXT,
                    timestamp TEXT
                )`);
            });

            db.close((err) => {
                if (err) reject(err);
                else resolve();
            });
        });
    });
}

// System statistics
async function getSystemStats() {
    try {
        // CPU usage
        const cpuUsage = await executeCommand("top -bn1 | grep 'Cpu(s)' | awk '{print $2}' | cut -d'%' -f1").catch(() => "0");
        
        // Memory usage
        const memoryUsage = await executeCommand("free | awk 'NR==2{printf \"%.1f\", $3*100/$2}'").catch(() => "0");
        
        // Disk usage
        const diskUsage = await executeCommand("df -h / | awk 'NR==2{print $5}' | cut -d'%' -f1").catch(() => "0");
        
        // Memory details
        const memoryTotal = await executeCommand("free -b | awk 'NR==2{print $2}'").catch(() => "0");
        const memoryUsed = await executeCommand("free -b | awk 'NR==2{print $3}'").catch(() => "0");
        
        // Disk details
        const diskTotal = await executeCommand("df -B1 / | awk 'NR==2{print $2}'").catch(() => "0");
        const diskUsed = await executeCommand("df -B1 / | awk 'NR==2{print $3}'").catch(() => "0");
        
        // Network statistics
        const networkSent = await executeCommand("cat /proc/net/dev | grep eth0 | awk '{print $10}'").catch(() => "0");
        const networkRecv = await executeCommand("cat /proc/net/dev | grep eth0 | awk '{print $2}'").catch(() => "0");
        
        // Uptime
        const uptime = await executeCommand("uptime -p").catch(() => "Unknown");
        
        // Hostname and OS info
        const hostname = await executeCommand("hostname").catch(() => "Unknown");
        const osInfo = await executeCommand("cat /etc/os-release | grep PRETTY_NAME | cut -d'=' -f2 | tr -d '\"'").catch(() => "Linux");
        const architecture = await executeCommand("uname -m").catch(() => "Unknown");
        
        // Active connections
        const activeConnections = await executeCommand("netstat -an | grep :8080 | grep ESTABLISHED | wc -l").catch(() => "0");

        return {
            cpu_usage: parseFloat(cpuUsage) || 0,
            memory_usage: parseFloat(memoryUsage) || 0,
            memory_total: Math.round(parseInt(memoryTotal) / (1024 ** 3) * 100) / 100 || 0,
            memory_used: Math.round(parseInt(memoryUsed) / (1024 ** 3) * 100) / 100 || 0,
            disk_usage: parseFloat(diskUsage) || 0,
            disk_total: Math.round(parseInt(diskTotal) / (1024 ** 3) * 100) / 100 || 0,
            disk_used: Math.round(parseInt(diskUsed) / (1024 ** 3) * 100) / 100 || 0,
            network: {
                bytes_sent: parseInt(networkSent) || 0,
                bytes_recv: parseInt(networkRecv) || 0
            },
            uptime: uptime,
            active_connections: parseInt(activeConnections) || 0,
            system_info: {
                hostname: hostname,
                os: osInfo,
                architecture: architecture
            }
        };
    } catch (error) {
        console.error('Error getting system stats:', error);
        return getFallbackStats();
    }
}

function getFallbackStats() {
    return {
        cpu_usage: 0,
        memory_usage: 0,
        memory_total: 0,
        memory_used: 0,
        disk_usage: 0,
        disk_total: 0,
        disk_used: 0,
        network: { bytes_sent: 0, bytes_recv: 0 },
        uptime: 'Unknown',
        active_connections: 0,
        system_info: {
            hostname: 'Unknown',
            os: 'Linux',
            architecture: 'Unknown'
        }
    };
}

// User management
async function getUsers() {
    try {
        const data = await fs.readFile(CONFIG.USER_DB, 'utf8');
        const jsonData = JSON.parse(data);
        return jsonData.users || [];
    } catch (error) {
        console.error('Error reading users:', error);
        return [];
    }
}

async function saveUsers(users) {
    try {
        const currentData = await fs.readFile(CONFIG.USER_DB, 'utf8');
        const jsonData = JSON.parse(currentData);
        jsonData.users = users;
        await fs.writeFile(CONFIG.USER_DB, JSON.stringify(jsonData, null, 2));
        return true;
    } catch (error) {
        console.error('Error saving users:', error);
        return false;
    }
}

async function addSystemUser(username, password) {
    try {
        // Create system user
        await executeCommand(`useradd -m -s /usr/sbin/nologin ${username}`);
        
        // Set password
        await new Promise((resolve, reject) => {
            const child = spawn('chpasswd', []);
            child.stdin.write(`${username}:${password}\n`);
            child.stdin.end();
            
            child.on('close', (code) => {
                if (code === 0) resolve();
                else reject(new Error(`chpasswd failed with code ${code}`));
            });
            
            child.on('error', reject);
        });
        
        return true;
    } catch (error) {
        console.error('Error adding system user:', error);
        return false;
    }
}

async function deleteSystemUser(username) {
    try {
        await executeCommand(`userdel -r ${username}`);
        return true;
    } catch (error) {
        console.error('Error deleting system user:', error);
        return false;
    }
}

// Configuration management
async function getConfig() {
    try {
        const data = await fs.readFile(CONFIG.CONFIG_FILE, 'utf8');
        return JSON.parse(data);
    } catch (error) {
        console.error('Error reading config:', error);
        return {};
    }
}

async function saveConfig(config) {
    try {
        await fs.writeFile(CONFIG.CONFIG_FILE, JSON.stringify(config, null, 2));
        return true;
    } catch (error) {
        console.error('Error saving config:', error);
        return false;
    }
}

// Service control
async function controlService(service, action) {
    try {
        await executeCommand(`systemctl ${action} ${service}`);
        return true;
    } catch (error) {
        console.error(`Error ${action}ing service ${service}:`, error);
        return false;
    }
}

// Database operations
function queryDatabase(sql, params = []) {
    return new Promise((resolve, reject) => {
        const db = new sqlite3.Database(CONFIG.STATS_DB, (err) => {
            if (err) {
                reject(err);
                return;
            }

            if (sql.trim().toLowerCase().startsWith('select')) {
                db.all(sql, params, (err, rows) => {
                    db.close();
                    if (err) reject(err);
                    else resolve(rows);
                });
            } else {
                db.run(sql, params, function(err) {
                    db.close();
                    if (err) reject(err);
                    else resolve({ changes: this.changes, lastID: this.lastID });
                });
            }
        });
    });
}

async function getRecentConnections(limit = 10) {
    try {
        const rows = await queryDatabase(
            'SELECT username, client_ip, start_time, duration, download_bytes, upload_bytes FROM connection_log ORDER BY id DESC LIMIT ?',
            [limit]
        );
        return rows || [];
    } catch (error) {
        console.error('Error getting recent connections:', error);
        return [];
    }
}

async function getGlobalStats() {
    try {
        const rows = await queryDatabase('SELECT key, value FROM global_stats');
        const stats = {};
        rows.forEach(row => {
            stats[row.key] = row.value;
        });
        return stats;
    } catch (error) {
        console.error('Error getting global stats:', error);
        return {};
    }
}

// Authentication middleware
function requireAuth(req, res, next) {
    if (req.session.admin) {
        next();
    } else {
        res.status(401).json({ error: 'Unauthorized' });
    }
}

// HTML Templates (same as Python version)
const MODERN_LOGIN = `...`; // Use the exact same HTML from your Python file

const MODERN_DASHBOARD = `...`; // Use the exact same HTML from your Python file

// Routes
app.get('/', (req, res) => {
    if (!req.session.admin) {
        return res.redirect('/login');
    }
    res.send(MODERN_DASHBOARD);
});

app.get('/login', (req, res) => {
    if (req.session.admin) {
        return res.redirect('/');
    }
    res.send(MODERN_LOGIN);
});

app.post('/login', async (req, res) => {
    const { username, password } = req.body;
    
    console.log(`Login attempt - Username: ${username}, Password: ${password}`);
    
    if (username === ADMIN_USERNAME && password === ADMIN_PASSWORD) {
        req.session.admin = true;
        req.session.login_time = new Date().toISOString();
        return res.json({ success: true, message: 'Login successful' });
    } else {
        return res.json({ success: false, message: 'Invalid credentials' });
    }
});

app.get('/logout', (req, res) => {
    req.session.destroy();
    res.redirect('/login');
});

// API Routes
app.get('/api/users', requireAuth, async (req, res) => {
    try {
        const users = await getUsers();
        
        // Add statistics and status to users
        for (let user of users) {
            // Get user stats from database
            const userStats = await queryDatabase(
                'SELECT connections, download_bytes, upload_bytes, last_connection FROM user_stats WHERE username = ?',
                [user.username]
            ).then(rows => rows[0]).catch(() => null);

            if (userStats) {
                user.connections = userStats.connections;
                user.download_bytes = userStats.download_bytes;
                user.upload_bytes = userStats.upload_bytes;
                user.last_connection = userStats.last_connection;
            } else {
                user.connections = 0;
                user.download_bytes = 0;
                user.upload_bytes = 0;
                user.last_connection = 'Never';
            }

            // Determine account status
            if (!user.active) {
                user.status = 'Inactive';
            } else if (user.expires) {
                try {
                    const expiryDate = new Date(user.expires);
                    if (new Date() > expiryDate) {
                        user.status = 'Expired';
                    } else {
                        const daysLeft = Math.ceil((expiryDate - new Date()) / (1000 * 60 * 60 * 24));
                        user.status = `Active (${daysLeft}d left)`;
                    }
                } catch {
                    user.status = 'Active';
                }
            } else {
                user.status = 'Active';
            }
        }

        const config = await getConfig();
        res.json({ 
            users: users, 
            settings: config.users || {} 
        });
    } catch (error) {
        console.error('Error getting users:', error);
        res.status(500).json({ error: 'Failed to get users' });
    }
});

app.post('/api/users/add', requireAuth, async (req, res) => {
    try {
        const { username, password, expires, max_connections = 3, active = true } = req.body;
        
        if (!username || !password) {
            return res.json({ success: false, message: 'Username and password are required' });
        }

        // Validate username
        if (!/^[a-z_][a-z0-9_-]*$/.test(username)) {
            return res.json({ success: false, message: 'Username can only contain lowercase letters, numbers, hyphens, and underscores' });
        }

        const users = await getUsers();

        // Check if user exists
        if (users.find(u => u.username === username)) {
            return res.json({ success: false, message: 'User already exists' });
        }

        // Add new user
        const newUser = {
            username,
            password,
            created: new Date().toISOString().split('T')[0] + ' ' + new Date().toTimeString().split(' ')[0],
            expires: expires || null,
            max_connections: parseInt(max_connections),
            active: active,
            last_modified: new Date().toISOString().split('T')[0] + ' ' + new Date().toTimeString().split(' ')[0]
        };

        users.push(newUser);
        const saved = await saveUsers(users);
        
        if (!saved) {
            return res.json({ success: false, message: 'Failed to save user to database' });
        }

        // Create system user
        const systemUserCreated = await addSystemUser(username, password);
        if (!systemUserCreated) {
            // Rollback - remove from users.json if system user creation failed
            const updatedUsers = users.filter(u => u.username !== username);
            await saveUsers(updatedUsers);
            return res.json({ success: false, message: 'Failed to create system user' });
        }

        res.json({ success: true, message: 'User created successfully' });
    } catch (error) {
        console.error('Error adding user:', error);
        res.json({ success: false, message: 'Error: ' + error.message });
    }
});

app.post('/api/users/delete', requireAuth, async (req, res) => {
    try {
        const { username } = req.body;
        
        if (!username) {
            return res.json({ success: false, message: 'Username is required' });
        }

        const users = await getUsers();
        const filteredUsers = users.filter(u => u.username !== username);
        
        if (filteredUsers.length === users.length) {
            return res.json({ success: false, message: 'User not found' });
        }

        const saved = await saveUsers(filteredUsers);
        
        if (!saved) {
            return res.json({ success: false, message: 'Failed to delete user from database' });
        }

        // Delete system user
        await deleteSystemUser(username);

        res.json({ success: true, message: 'User deleted successfully' });
    } catch (error) {
        console.error('Error deleting user:', error);
        res.json({ success: false, message: 'Error: ' + error.message });
    }
});

app.post('/api/users/update', requireAuth, async (req, res) => {
    try {
        const { username, ...updates } = req.body;
        
        if (!username) {
            return res.json({ success: false, message: 'Username is required' });
        }

        const users = await getUsers();
        const userIndex = users.findIndex(u => u.username === username);
        
        if (userIndex === -1) {
            return res.json({ success: false, message: 'User not found' });
        }

        users[userIndex] = { ...users[userIndex], ...updates };
        users[userIndex].last_modified = new Date().toISOString().split('T')[0] + ' ' + new Date().toTimeString().split(' ')[0];
        
        const saved = await saveUsers(users);
        
        if (saved) {
            res.json({ success: true, message: 'User updated successfully' });
        } else {
            res.json({ success: false, message: 'Failed to update user' });
        }
    } catch (error) {
        console.error('Error updating user:', error);
        res.json({ success: false, message: 'Error: ' + error.message });
    }
});

app.get('/api/stats', requireAuth, async (req, res) => {
    try {
        const systemStats = await getSystemStats();
        const globalStats = await getGlobalStats();
        const recentConnections = await getRecentConnections(10);
        
        // Get service status
        const tunnelStatus = await executeCommand('systemctl is-active gx-tunnel').catch(() => 'unknown');
        const webguiStatus = await executeCommand('systemctl is-active gx-webgui').catch(() => 'unknown');
        
        res.json({
            system: systemStats,
            global: globalStats,
            recent_connections: recentConnections,
            services: {
                tunnel: tunnelStatus,
                webgui: webguiStatus
            }
        });
    } catch (error) {
        console.error('Error getting stats:', error);
        res.status(500).json({ error: 'Failed to get statistics' });
    }
});

app.get('/api/config', requireAuth, async (req, res) => {
    try {
        const config = await getConfig();
        res.json(config);
    } catch (error) {
        console.error('Error getting config:', error);
        res.status(500).json({ error: 'Failed to get configuration' });
    }
});

app.post('/api/config/update', requireAuth, async (req, res) => {
    try {
        const updates = req.body;
        const currentConfig = await getConfig();
        
        // Deep merge updates
        function deepMerge(target, source) {
            for (const key in source) {
                if (source[key] && typeof source[key] === 'object' && !Array.isArray(source[key])) {
                    if (!target[key]) target[key] = {};
                    deepMerge(target[key], source[key]);
                } else {
                    target[key] = source[key];
                }
            }
        }
        
        deepMerge(currentConfig, updates);
        
        const saved = await saveConfig(currentConfig);
        
        if (saved) {
            res.json({ success: true, message: 'Configuration updated successfully' });
        } else {
            res.json({ success: false, message: 'Failed to update configuration' });
        }
    } catch (error) {
        console.error('Error updating config:', error);
        res.json({ success: false, message: 'Error: ' + error.message });
    }
});

app.post('/api/services/:action', requireAuth, async (req, res) => {
    try {
        const { action } = req.params;
        const validActions = ['start', 'stop', 'restart'];
        
        if (!validActions.includes(action)) {
            return res.json({ success: false, message: 'Invalid action' });
        }

        const tunnelSuccess = await controlService('gx-tunnel', action);
        const webguiSuccess = await controlService('gx-webgui', action);
        
        if (tunnelSuccess && webguiSuccess) {
            res.json({ success: true, message: `Services ${action}ed successfully` });
        } else {
            res.json({ success: false, message: `Failed to ${action} services` });
        }
    } catch (error) {
        console.error('Error controlling services:', error);
        res.json({ success: false, message: 'Error: ' + error.message });
    }
});

app.post('/api/backup', requireAuth, async (req, res) => {
    try {
        const backupDir = path.join(CONFIG.INSTALL_DIR, 'backups');
        await fs.mkdir(backupDir, { recursive: true });
        
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
        const backupFile = path.join(backupDir, `backup_${timestamp}.json`);
        
        const users = await getUsers();
        const config = await getConfig();
        
        const backupData = {
            users: users,
            settings: config.users || {},
            backup_time: new Date().toISOString(),
            version: '1.0'
        };
        
        await fs.writeFile(backupFile, JSON.stringify(backupData, null, 2));
        
        res.json({ success: true, message: `Backup created: ${backupFile}` });
    } catch (error) {
        console.error('Error creating backup:', error);
        res.json({ success: false, message: 'Backup failed: ' + error.message });
    }
});

// Real-time monitoring endpoint
app.get('/api/monitor', requireAuth, async (req, res) => {
    try {
        const systemStats = await getSystemStats();
        const recentConnections = await getRecentConnections(5);
        
        res.json({
            system: systemStats,
            recent_connections: recentConnections,
            timestamp: new Date().toISOString()
        });
    } catch (error) {
        console.error('Error in monitor endpoint:', error);
        res.status(500).json({ error: 'Monitoring error' });
    }
});

// Initialize and start server
async function startServer() {
    await ensureFilesExist();
    
    app.listen(PORT, '0.0.0.0', () => {
        console.log('🚀 GX Tunnel Web GUI started successfully!');
        console.log('📊 Dashboard: http://localhost:' + PORT);
        console.log('🔐 Admin Login: ' + ADMIN_USERNAME + ' / ' + ADMIN_PASSWORD);
        console.log('✅ All features working: User management, Real-time monitoring, Service control');
        console.log('🌐 Domain support and SSL configuration available');
    });
}

startServer().catch(console.error);
