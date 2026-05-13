# Kong Gateway Setup — apptronium.com

Kong Gateway OSS setup for apptronium.com. Routes web traffic to backend services using subdomains, with Nginx handling HTTPS and PostgreSQL as the database. Configured with Docker Compose and managed declaratively with decK.

---

## Architecture

```
Internet (80/443)
     │
     ▼
  Nginx  ← HTTPS termination (Let's Encrypt)
     │
     ├──→ Kong :8000  ← routes by subdomain (Host header)
     │         └──→ ratesageai container :3000
     │
     └──→ Jenkins :8080

PostgreSQL 17
  ├── kong          (Kong internals)
  └── app_ratesageai
```

- **Nginx** — the only public-facing component. Terminates TLS and forwards traffic.
- **Kong** — receives plain HTTP from Nginx internally. Routes requests to the right backend service based on the subdomain.
- **PostgreSQL 17** — shared database. Each service gets its own database and user.
- **decK** — CLI tool installed on the host. Syncs `kong/kong.yaml` to Kong via the Admin API.

---

## Repository Structure

```
kong_gateway_setup/
├── .env.example                 ← copy to .env and fill in secrets
├── commands.txt                 ← ordered setup and ops commands
├── nginx/
│   ├── docker-compose.yml
│   └── conf.d/
│       └── apptronium.com.conf  ← all Nginx server blocks
├── kong/
│   ├── docker-compose.yml
│   └── kong.yaml                ← declarative Kong config (decK)
├── postgres17/
│   ├── docker-compose.yml
│   └── initdb.d/
│       └── 01-init.sh           ← creates databases and users on first start
└── jenkins/
    └── docker-compose.yml
```

---

## Prerequisites

- Docker + Docker Compose on the VPS
- Certbot installed on the host OS (`sudo apt install certbot`)
- decK installed on the host OS (see `commands.txt`)
- DNS A records pointing all subdomains to the VPS IP

---

## First-Time Setup

See `commands.txt` for the full ordered list of commands. The high-level steps are:

1. Copy `.env.example` to `.env` and set real passwords
2. Create the shared Docker network: `docker network create apptronium_net`
3. Start Nginx (HTTP only), obtain SSL certs via Certbot
4. Start PostgreSQL
5. Run Kong migrations, then start Kong
6. Push Kong config: `deck sync -s kong/kong.yaml --kong-addr http://localhost:8001`
7. Reload Nginx to activate HTTPS

---

## Day-to-Day Operations

| Task | Command |
|---|---|
| Apply Kong config changes | `deck sync -s kong/kong.yaml --kong-addr http://localhost:8001` |
| Reload Nginx | `docker exec nginx_production nginx -s reload` |
| Check Kong routes | `curl http://localhost:8001/routes` |
| Cert renewal dry run | `sudo certbot renew --dry-run` |

---

## Adding a New Service

1. **DNS** — Add an A record for the new subdomain
2. **Certificate** — Re-run `certbot certonly --webroot` with `--expand` and all subdomains
3. **Nginx** — Add a `server` block in `nginx/conf.d/apptronium.com.conf`
4. **Kong** — Add a service + route entry in `kong/kong.yaml`, then `deck sync`
5. **Database** — Create a new user and database (see `commands.txt`)
6. **Verify** — `curl -I https://newservice.apptronium.com/health`

---

## Environment Variables

Copy `.env.example` to `.env` and fill in real values. The `.env` file is git-ignored and must never be committed.

| Variable | Purpose |
|---|---|
| `POSTGRES_USER` | PostgreSQL superuser name |
| `POSTGRES_PASSWORD` | PostgreSQL superuser password |
| `KONG_PG_PASSWORD` | Password for the `kong` database user |
| `APP_RATESAGEAI_PASSWORD` | Password for the `app_ratesageai` database user |
