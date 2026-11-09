# Restauranty

A restaurant management platform built with a **microservices architecture**: 3 Node.js/Express backends + a React frontend, unified behind HAProxy path-based routing.

## Architecture

```
                         ┌────────────────────────┐
                         │   HAProxy / Ingress    │
    Browser ───────────► │       (port 80)        │
                         └───────────┬────────────┘
                                     │
            ┌────────────────────────┼─────────────────────────┐
            │                        │                         │
       /api/auth/*             /api/items/*             /api/discounts/*
            │                        │                         │
   ┌────────▼────────┐     ┌─────────▼─────────┐    ┌─────────▼──────────┐
   │  Auth Service   │     │  Items Service    │    │ Discounts Service  │
   │   (port 3001)   │     │   (port 3003)     │    │   (port 3002)      │
   └────────┬────────┘     └─────────┬─────────┘    └──────────┬─────────┘
            │                        │                         │
            └────────────────────────┼─────────────────────────┘
                                     │
                              ┌──────▼──────┐
                              │   MongoDB   │
                              │ (port 27017)│
                              └─────────────┘
```

## Microservices

| Service | Port | Path | Responsibilities |
|---------|------|------|-----------------|
| **Auth** | 3001 | `/api/auth/*` | User signup, login, JWT authentication |
| **Discounts** | 3002 | `/api/discounts/*` | Coupon and campaign management |
| **Items** | 3003 | `/api/items/*` | Menu items, dietary categories, orders |
| **Frontend** | 3000 | `/` | React SPA (admin dashboard) |

## Quick Start

Requires **Node.js 20 or newer** (tested on Node 24) and Docker.

### 1. Start MongoDB

```bash
docker run -d \
  --name my-mongo \
  -p 27017:27017 \
  -v mongo-data:/data/db \
  mongo:8
```

### 2. Start each microservice

```bash
# Terminal 1 - Auth
cd backend/auth && npm install && npm start

# Terminal 2 - Discounts
cd backend/discounts && npm install && npm start

# Terminal 3 - Items
cd backend/items && npm install && npm start

# Terminal 4 - Frontend
cd client && npm install && npm start
```

### 3. Start HAProxy

```bash
haproxy -f haproxy.cfg
```

Access the app at **http://localhost/**

## Environment Variables

Each microservice reads its settings from a `.env` file (copy `.env.example` in each service folder):

| Variable | Used by | Description | Example |
|----------|---------|-------------|---------|
| `JWT_PRIVATE_KEY` | auth only | RS256 private key that signs login tokens | see [JWT keys](#jwt-keys) |
| `JWT_PUBLIC_KEY` | discounts, items | RS256 public key that checks login tokens | see [JWT keys](#jwt-keys) |
| `JWT_ISSUER`, `JWT_AUDIENCE` | all | Who issues the token and who it is for; checked on every request | `restauranty-auth`, `restauranty-api` |
| `MONGODB_URI` | all | MongoDB connection string | `mongodb://127.0.0.1:27017/restauranty` |
| `CLOUD_NAME` | items | Cloudinary cloud name | _(ask instructor)_ |
| `CLOUD_API_KEY` | items | Cloudinary API key | _(ask instructor)_ |
| `CLOUD_API_SECRET` | items | Cloudinary API secret | _(ask instructor)_ |
| `PORT` | all | Service port | `3001` / `3002` / `3003` |

For the frontend, use the `REACT_APP_` prefix: `REACT_APP_API_URL=http://localhost:80`

### JWT keys

Login tokens are signed with RS256: a key pair instead of one shared secret. auth signs with the private key. discounts and items check tokens with the public key, which cannot create tokens. A service without a valid key refuses to start.

Create a key pair (`*.pem` files are git-ignored):

```bash
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out jwt-private.pem
openssl pkey -in jwt-private.pem -pubout -out jwt-public.pem
```

Write the keys into the `.env` files, as one line each:

```bash
# set_key <file> <variable> <pem file>: replaces the variable's line with the key on one line
set_key() {
  grep -v "^$2=" "$1" > "$1.tmp"
  printf '%s="%s"\n' "$2" "$(awk '{printf "%s\\n", $0}' "$3")" >> "$1.tmp"
  mv "$1.tmp" "$1"
}
set_key backend/auth/.env      JWT_PRIVATE_KEY jwt-private.pem
set_key backend/discounts/.env JWT_PUBLIC_KEY  jwt-public.pem
set_key backend/items/.env     JWT_PUBLIC_KEY  jwt-public.pem
```

On AKS the keys come from Azure Key Vault instead.

## Tech Stack

- **Frontend**: React 18, React Router 6, Tailwind CSS, Axios, React Icons
- **Backend**: Express, Mongoose, JWT (jsonwebtoken + express-jwt), bcryptjs
- **Image Storage**: Cloudinary (via multer-storage-cloudinary)
- **Monitoring**: Prometheus metrics (`/metrics` endpoint on each backend service)
- **Routing**: HAProxy (local) / Kubernetes Ingress (production)
- **Database**: MongoDB
