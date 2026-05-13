# Kong Gateway Setup — apptronium.com

## Project Goal

Migrate the `apptronium.com` VPS from APISIX to Kong Gateway OSS.  
Replace path-based API routing with per-service subdomain routing.  
Adopt PostgreSQL 17 as a shared database for Kong and application containers.

---

## Current Architecture (being replaced)

- **Nginx** — public-facing reverse proxy, HTTPS termination
- **APISIX** — API gateway, path-based routing
  - `apigw.apptronium.com/service-one`
  - `apigw.apptronium.com/service-two`
- **APISIX Dashboard** — `apisix.apptronium.com`
- **Jenkins** — `jenkins.apptronium.com`

---

## Target Architecture

```
Internet (80/443)
     │
     ▼
  Nginx  ← HTTPS termination, only public-facing component
     │
     ├──→ Kong (internal)  ← routes by Host header
     │         │
     │         ├──→ ratesageai container
     │         └──→ (future services)
     │
     └──→ Jenkins (jenkins.apptronium.com)

PostgreSQL 17 (shared)
  ├── database: kong
  └── database: app_ratesageai
```

---

## Key Architectural Decisions

| Concern | Decision |
|---|---|
| Public entry point | Nginx only |
| TLS termination | Nginx (Certbot, Let's Encrypt) |
| API gateway | Kong OSS (replaces APISIX) |
| Kong routing | Host-header based (one subdomain per service) |
| Kong config management | `deck` (declarative YAML, version-controlled) |
| Kong Admin API | Internal only — never publicly exposed |
| Database | PostgreSQL 17, shared instance, one DB per service |
| Jenkins | Retained at `jenkins.apptronium.com`, proxied directly by Nginx |

---

## Infrastructure Details

### Docker Network

Single Docker network for all containers:

```
apptronium_net
```

Created with:
```
docker network create apptronium_net
```

### Docker Volumes (planned)

| Volume | Purpose |
|---|---|
| `postgres_data` | PostgreSQL persistent storage |
| `kong_prefix` | Kong runtime prefix dir |

Nginx config and Certbot certs are bind-mounted from host paths.

### Certbot — HTTPS Certificate Setup

Certbot is installed **on the host OS** (not containerized).

```bash
sudo apt update && sudo apt install certbot -y
```

Webroot directory (served by the Nginx container):
```
/var/www/certbot
```

Certificate issuance command pattern:
```bash
sudo certbot certonly --webroot -w /var/www/certbot \
  -d apptronium.com \
  -d www.apptronium.com \
  -d <new-subdomain>.apptronium.com \
  --agree-tos
```

After updating Nginx config, reload without downtime:
```bash
docker exec <nginx-container-name> nginx -s reload
```

Certbot renewal hook should exec the above reload command inside the Nginx container.

### Current Certificates

Domains covered by existing Let's Encrypt cert:
- `apptronium.com`
- `www.apptronium.com`
- `apigw.apptronium.com`
- `apisix.apptronium.com`
- `jenkins.apptronium.com`

New service subdomains must be added via `certbot --expand` or a fresh `certonly` run with the full `-d` list.

---

## Routing Responsibilities

### Nginx

- Terminates TLS for all subdomains
- Forwards all API traffic to Kong on the internal Docker network
- Preserves the `Host` header so Kong can match routes
- Required proxy headers: `Host`, `X-Real-IP`, `X-Forwarded-For`, `X-Forwarded-Proto`
- Does **not** know about individual backend services

### Kong

- Receives plain HTTP from Nginx (internal network only)
- Routes requests to backend containers by `Host` header
- Manages plugins: rate limiting, auth, CORS, etc.
- Configured declaratively via `deck sync`
- Admin API (port 8001) is never exposed outside the Docker network

---

## Adding a New Service Subdomain

Follow these steps each time a new service (e.g., `service-three.apptronium.com`) is added:

1. **DNS** — Add an A record: `service-three.apptronium.com` → VPS IP
2. **Certificate** — Re-run `certbot certonly --webroot` with the expanded `-d` list
3. **Nginx** — Add a `server` block for the new subdomain (or rely on wildcard block if configured)
4. **Compose** — Add the new service container, join it to `apptronium_net`
5. **Kong** — Add service + route to the `deck` config YAML, run `deck sync`
6. **Verify** — `curl -I https://service-three.apptronium.com/health`

---

## PostgreSQL Strategy

One PostgreSQL 17 container, multiple databases:

- `kong` — owned by `kong` user, used only by Kong
- `app_ratesageai` — RateSageAI service database, owned by `app_ratesageai` user
- `app_<future-service>` — one per additional service, each with its own user

All credentials stored in `.env` (never committed to git).

Initialization scripts in `postgres17/initdb.d/` create databases and users on first start.

PostgreSQL is only reachable within `apptronium_net`. No host port binding.

---

## Workflow Reference

### Start the stack for the first time

```bash
# 1. Create network (if not exists)
docker network create apptronium_net

# 2. Start Postgres first
docker compose up -d postgres

# 3. Run Kong migrations
docker compose run --rm kong-migrations

# 4. Start remaining services
docker compose up -d

# 5. Obtain/expand SSL certs
sudo certbot certonly --webroot -w /var/www/certbot -d ... --agree-tos

# 6. Reload Nginx
docker exec <nginx-container> nginx -s reload

# 7. Push Kong config
deck sync -s kong/kong.yaml
```

### Verify after deployment

```bash
# Kong Admin API (from VPS, internal only)
curl http://localhost:8001/routes

# End-to-end HTTPS check
curl -I https://service-one.apptronium.com/health

# Certificate renewal dry run
sudo certbot renew --dry-run
```

---

## Files in This Repository (planned)

```
kong_gateway_setup/
├── CLAUDE.md                  ← this file
├── .env.example               ← template for secrets
├── commands.txt               ← ordered setup and ops commands
├── nginx/
│   ├── docker-compose.yml
│   └── conf.d/
│       └── apptronium.com.conf  ← all server blocks (main site + Kong proxy)
├── kong/
│   ├── docker-compose.yml
│   └── kong.yaml              ← declarative deck config
└── postgres17/
    ├── docker-compose.yml
    └── initdb.d/
        └── 01-init.sh         ← create databases and users from env vars
```
