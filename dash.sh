#!/bin/bash
set -e

# Update system
sudo apt update && sudo apt upgrade -y

# Install dependencies
sudo apt install -y curl git build-essential

# Install Node.js (LTS)
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# Install PM2 (for process management)
sudo npm install -g pm2

# Clone your repo
if [ ! -d "dash" ]; then
  git clone https://github.com/Vedoxion/dash.git
fi

cd dash

# Install backend + frontend deps
if [ -f "package.json" ]; then
  npm install
fi

if [ -d "frontend" ] && [ -f "frontend/package.json" ]; then
  cd frontend
  npm install
  npm run build
  cd ..
fi

# Start backend with PM2
pm2 start npm --name "dash-backend" -- run start
pm2 save

echo "✅ Victus Dash installed and running!"
echo "You can manage it with: pm2 status | pm2 logs dash-backend"
