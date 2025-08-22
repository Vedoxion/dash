#!/usr/bin/env bash
set -euo pipefail

REPO="victuscloud-dashboard"
echo "Scaffolding $REPO ..."
mkdir -p "$REPO"/{backend/{routes,utils,data},frontend/src/{components,pages}}
cd "$REPO"

#####################################
# Backend
#####################################
cat > backend/.env.example <<'EOF'
# ===== VictusCloud Dashboard - Backend .env =====
PORT=4000
CORS_ORIGIN=http://localhost:5173

# Discord OAuth2
DISCORD_CLIENT_ID=YOUR_DISCORD_CLIENT_ID
DISCORD_CLIENT_SECRET=YOUR_DISCORD_CLIENT_SECRET
DISCORD_REDIRECT_URI=http://localhost:4000/api/auth/discord/callback

# JWT secret for signing user sessions
JWT_SECRET=supersecret_change_me

# Pterodactyl Panel
PTERO_BASE_URL=https://panel.example.com
PTERO_API_KEY=ptla_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
EOF

cat > backend/package.json <<'EOF'
{
  "name": "victuscloud-backend",
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "dev": "node server.js",
    "start": "node server.js"
  },
  "dependencies": {
    "axios": "^1.6.7",
    "cookie-parser": "^1.4.6",
    "cors": "^2.8.5",
    "dotenv": "^16.3.1",
    "express": "^4.19.2",
    "jsonwebtoken": "^9.0.2",
    "morgan": "^1.10.0",
    "qs": "^6.12.1"
  }
}
EOF

cat > backend/server.js <<'EOF'
import express from 'express';
import morgan from 'morgan';
import cors from 'cors';
import cookieParser from 'cookie-parser';
import dotenv from 'dotenv';

import authRouter from './routes/auth.js';
import userRouter from './routes/user.js';
import pteroRouter from './routes/ptero.js';

dotenv.config();
const app = express();
app.use(morgan('dev'));
app.use(express.json());
app.use(cookieParser());
app.use(cors({
  origin: process.env.CORS_ORIGIN?.split(',') || ['http://localhost:5173'],
  credentials: true
}));

app.get('/api/health', (req,res)=> {
  res.json({ ok: true, service: 'VictusCloud Backend', time: new Date().toISOString() });
});

app.use('/api/auth', authRouter);
app.use('/api/user', userRouter);
app.use('/api/ptero', pteroRouter);

const PORT = process.env.PORT || 4000;
app.listen(PORT, ()=> console.log(`VictusCloud backend listening on ${PORT}`));
EOF

cat > backend/utils/jwt.js <<'EOF'
import jwt from 'jsonwebtoken';
export function signToken(payload) {
  return jwt.sign(payload, process.env.JWT_SECRET, { expiresIn: '7d' });
}
export function verifyToken(token) {
  try { return jwt.verify(token, process.env.JWT_SECRET); }
  catch { return null; }
}
export function authRequired(req, res, next) {
  const token = req.cookies?.vc_token || (req.headers.authorization?.split(' ')[1]);
  if (!token) return res.status(401).json({ error: 'Unauthorized' });
  const decoded = verifyToken(token);
  if (!decoded) return res.status(401).json({ error: 'Invalid token' });
  req.user = decoded;
  next();
}
EOF

cat > backend/routes/auth.js <<'EOF'
import { Router } from 'express';
import dotenv from 'dotenv';
import axios from 'axios';
import qs from 'qs';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { signToken } from '../utils/jwt.js';

dotenv.config();
const router = Router();
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const USERS_PATH = path.join(__dirname, '..', 'data', 'users.json');

function loadUsers(){ try { return JSON.parse(fs.readFileSync(USERS_PATH,'utf-8')); } catch { return { users: [] }; } }
function saveUsers(db){ fs.writeFileSync(USERS_PATH, JSON.stringify(db, null, 2)); }

router.get('/discord/login', (req,res)=>{
  const params = new URLSearchParams({
    client_id: process.env.DISCORD_CLIENT_ID,
    redirect_uri: process.env.DISCORD_REDIRECT_URI,
    response_type: 'code',
    scope: 'identify email'
  });
  res.redirect(`https://discord.com/api/oauth2/authorize?${params.toString()}`);
});

router.get('/discord/callback', async (req,res)=>{
  const code = req.query.code;
  if (!code) return res.status(400).send('Missing code');
  try {
    const tokenRes = await axios.post('https://discord.com/api/oauth2/token', qs.stringify({
      client_id: process.env.DISCORD_CLIENT_ID,
      client_secret: process.env.DISCORD_CLIENT_SECRET,
      grant_type: 'authorization_code',
      code,
      redirect_uri: process.env.DISCORD_REDIRECT_URI
    }), { headers: { 'Content-Type': 'application/x-www-form-urlencoded' }});

    const access_token = tokenRes.data.access_token;
    const userRes = await axios.get('https://discord.com/api/users/@me', {
      headers: { Authorization: `Bearer ${access_token}` }
    });
    const duser = userRes.data;

    const db = loadUsers();
    let u = db.users.find(x=> x.discord_id === duser.id);
    if (!u) {
      u = {
        id: db.users.length + 1,
        discord_id: duser.id,
        username: duser.username,
        avatar: duser.avatar,
        email: duser.email || null,
        coins: 100,
        role: 'user',
        created_at: new Date().toISOString()
      };
      db.users.push(u);
      saveUsers(db);
    }
    const token = signToken({ id: u.id, username: u.username, role: u.role });
    res.cookie('vc_token', token, { httpOnly: true, sameSite: 'Lax' });

    const frontend = process.env.CORS_ORIGIN?.split(',')[0] || 'http://localhost:5173';
    res.redirect(`${frontend}/auth/callback`);
  } catch (e) {
    console.error(e.response?.data || e.message);
    res.status(500).json({ error: 'Discord OAuth failed' });
  }
});

router.post('/logout', (req,res)=>{
  res.clearCookie('vc_token');
  res.json({ ok: true });
});

export default router;
EOF

cat > backend/routes/user.js <<'EOF'
import { Router } from 'express';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { authRequired } from '../utils/jwt.js';

const router = Router();
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const USERS_PATH = path.join(__dirname, '..', 'data', 'users.json');

function loadUsers(){ try { return JSON.parse(fs.readFileSync(USERS_PATH,'utf-8')); } catch { return { users: [] }; } }
function saveUsers(db){ fs.writeFileSync(USERS_PATH, JSON.stringify(db, null, 2)); }

router.get('/me', authRequired, (req,res)=>{
  const db = loadUsers();
  const me = db.users.find(u=> u.id === req.user.id);
  res.json({ user: me || null });
});

router.post('/coins/add', authRequired, (req,res)=>{
  const chunks = [];
  req.on('data', c=> chunks.push(c));
  req.on('end', ()=>{
    const body = chunks.length ? JSON.parse(Buffer.concat(chunks).toString()) : {};
    const { amount } = body;
    const db = loadUsers();
    const me = db.users.find(u=> u.id === req.user.id);
    if (!me) return res.status(404).json({ error: 'User not found' });
    me.coins = (me.coins || 0) + Number(amount || 0);
    saveUsers(db);
    res.json({ coins: me.coins });
  });
});

router.post('/coins/spend', authRequired, (req,res)=>{
  const chunks = [];
  req.on('data', c=> chunks.push(c));
  req.on('end', ()=>{
    const body = chunks.length ? JSON.parse(Buffer.concat(chunks).toString()) : {};
    const { amount } = body;
    const db = loadUsers();
    const me = db.users.find(u=> u.id === req.user.id);
    if (!me) return res.status(404).json({ error: 'User not found' });
    const a = Number(amount || 0);
    if (me.coins < a) return res.status(400).json({ error: 'Not enough coins' });
    me.coins -= a;
    saveUsers(db);
    res.json({ coins: me.coins });
  });
});

export default router;
EOF

cat > backend/routes/ptero.js <<'EOF'
import { Router } from 'express';
import axios from 'axios';
import dotenv from 'dotenv';
import { authRequired } from '../utils/jwt.js';

dotenv.config();
const router = Router();

const client = axios.create({
  baseURL: process.env.PTERO_BASE_URL,
  headers: {
    'Authorization': `Bearer ${process.env.PTERO_API_KEY}`,
    'Content-Type': 'application/json',
    'Accept': 'application/json'
  }
});

router.get('/servers', authRequired, async (req,res)=>{
  try {
    const r = await client.get('/api/client');
    res.json(r.data);
  } catch (e) {
    res.status(500).json({ error: 'Pterodactyl request failed', detail: e.response?.data || e.message });
  }
});

router.get('/proxy', authRequired, async (req,res)=>{
  const { path } = req.query; // e.g., /api/client
  if (!path || typeof path !== 'string') return res.status(400).json({ error: 'path is required' });
  try {
    const r = await client.get(path);
    res.json(r.data);
  } catch (e) {
    res.status(500).json({ error: 'Proxy failed', detail: e.response?.data || e.message });
  }
});

export default router;
EOF

cat > backend/README.md <<'EOF'
# VictusCloud Backend

**Features**
- Discord OAuth2 login (`/api/auth/discord/login`)
- JWT cookie session (`vc_token`)
- Simple JSON user store (`data/users.json`) with `coins`
- Pterodactyl API proxy (`/api/ptero/servers`)

## Setup
```bash
cd backend
cp .env.example .env
npm install
npm run dev
