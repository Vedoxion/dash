#!/bin/bash

# VictusCloud One-Click Installer 🚀
# Author: VictusCloud Setup

echo "====================================="
echo "   VictusCloud Installer - Starting  "
echo "====================================="

# Update system
sudo apt update && sudo apt upgrade -y

# Install dependencies
echo "[+] Installing dependencies..."
sudo apt install -y curl git build-essential nginx

# Install Node.js (LTS)
echo "[+] Installing Node.js..."
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt install -y nodejs
sudo npm install -g pm2

# Clone VictusCloud Dashboard repo
echo "[+] Cloning VictusCloud Dashboard..."
cd /var/www
sudo git clone https://github.com/YourUser/VictusCloud-Dashboard.git
cd VictusCloud-Dashboard

# Install backend
echo "[+] Setting up backend..."
cd backend
npm install
pm2 start server.js --name victus-backend
pm2 save

# Install frontend
echo "[+] Setting up frontend..."
cd ../frontend
npm install
npm run build

# Configure Nginx
echo "[+] Configuring Nginx..."
sudo tee /etc/nginx/sites-available/victuscloud > /dev/null <<EOL
server {
    listen 80;
    server_name _;

    root /var/www/VictusCloud-Dashboard/frontend/build;

    index index.html index.htm;

    location / {
        try_files \$uri /index.html;
    }

    location /api/ {
        proxy_pass http://localhost:5000/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOL

sudo ln -s /etc/nginx/sites-available/victuscloud /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl restart nginx

echo "====================================="
echo " ✅ VictusCloud Installed Successfully!"
echo " Open your VPS IP in browser to view "
echo "====================================="
