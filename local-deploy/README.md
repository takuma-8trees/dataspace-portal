Reproducing Data Space Portal (production-like) locally via Docker Compose

Overview
--------
This folder contains a minimal Docker Compose stack that reproduces the production deployment topology on a Docker network:
- Keycloak (24.0.4)
- Postgres (16)
- OAuth2 Proxy (7.5.0)
- Caddy (2.7) acting as a simple reverse proxy
- Authority Portal Backend and Frontend (images from GHCR)

Important: this is a convenience reproduction for local testing only. You still need to:
- Import the Keycloak realm (`authority-portal`) from the repo (`authority-portal-backend/.../realm.json`) into Keycloak
- Create/regenerate client secrets for `oauth2-proxy` and `authority-portal-client` in Keycloak and copy them into `.env`
- Fill in the secrets in `.env` (copy `.env.sample` to `.env`)

How to run
----------
1. Copy and edit environment variables

   cp .env.sample .env
   # Edit .env and replace placeholders with secure values

2. Start the stack

   docker compose up -d

3. Access the services

   - Frontend (via Caddy): http://localhost
   - Keycloak admin console: http://localhost:8080 (user/password from your .env)
   - OAuth2 Proxy debug port (direct): http://localhost:4180

Manual steps required after starting
----------------------------------
1. Import the realm into Keycloak:
   - Use the realm JSON from the repository:
     `authority-portal-backend/authority-portal-quarkus/src/main/resources/realm.json`
   - In Keycloak Admin UI: Import realm or use Keycloak Admin CLI

2. Create/regenerate client secrets for `oauth2-proxy` and `authority-portal-client`:
   - After creating/regenerating, copy `oauth2-proxy` client secret to `OAUTH2_PROXY_CLIENT_SECRET` in `.env`
   - Copy `authority-portal-client` client secret to `AP_CLIENT_SECRET` in `.env`

3. (Optional) Adjust Caddyfile if you want HTTPS locally or different ports.

Notes / Caveats
----------------
- The backend expects a database named `authority_portal`. If it isn't present, the backend may attempt to initialize it on first run. If it fails, create it manually in Postgres.
- This reproduction uses public GHCR images (`ghcr.io/sovity/authority-portal-backend` and `ghcr.io/sovity/authority-portal-frontend`). If you want to build local images (e.g. from source), replace the `image:` entries with `build:` contexts.
- The OAuth2 Proxy configuration here is minimal for local testing; production setups must harden cookie secrets, TLS, redirect URLs and cookie settings.

Catalog Crawler (local notes)
----------------------------
- The catalog crawler is an EDC-based component that requires:
   - A reachable Postgres DB (it stores crawler logs and measurements)
   - A DAPS/OAuth provider (Keycloak) and an SKI/AKI client id (the crawler's EDC client)
   - Connectors (EDC instances) registered in the same DAPS to actually crawl

- Environment variables provided in `.env.sample` (copy to `.env` and edit):
   - `CRAWLER_EDC_CLIENT_ID` — client id (SKI/AKI) for the crawler in Keycloak/DAPS
   - `CRAWLER_DB_JDBC_URL`, `CRAWLER_DB_JDBC_USER`, `CRAWLER_DB_JDBC_PASSWORD` — DB connection for crawler
   - `CRAWLER_ENVIRONMENT_ID` — environment id (e.g. `test`)
   - `MY_EDC_FQDN` — public FQDN used by the crawler

- The compose file exposes the crawler on port `11003` (host -> container mapping). After the stack is up, you can check the crawler endpoint at:

   http://localhost:11003

- The crawler will only fetch catalogs if there are connectors registered in the same DAPS/realm and the crawler has valid credentials to access them.

Logging House (local notes)
--------------------------
- For local testing I added a small HTTP stub that returns OK; this simulates a reachable Logging House endpoint used by the portal UI and by EDC logging extensions. Replace the stub with your real logging-house image if available.

Try it (quick)
--------------
# dataspace-portal/local-deploy

Reproduce a production-like Dataspace Portal stack locally using Docker Compose.

This folder contains a convenience Docker Compose setup that brings up the main services used in the Dataspace Portal production topology on a single Docker network. It's intended for local development and testing only.

## Services included (minimal reproduction)
- Keycloak (quay.io/keycloak/keycloak)
- PostgreSQL (postgres:16)
- oauth2-proxy (quay.io/oauth2-proxy/oauth2-proxy)
- Caddy (caddy:2.7) as a simple reverse proxy / TLS terminator
- Authority Portal backend and frontend (public GHCR images)
- Catalog crawler (EDC-based) and a small HTTP stub used as a Logging House placeholder

## Important notes
- This repository contains a Keycloak realm JSON that must be imported into Keycloak (see below). The compose setup does not automatically embed client secrets for security reasons.
- Copy `.env.sample` to `.env` and fill in secrets (Postgres password, Keycloak admin password, oauth2-proxy cookie secret, client secrets, etc.).
- This setup is for local/dev use only. Do not use it as-is in production. See the TLS section for production guidance.

## Quickstart
1. Copy the sample environment file and edit values:

```bash
cp .env.sample .env
# Edit .env and provide secure values for at least:
# POSTGRES_PASSWORD, KEYCLOAK_ADMIN_PASSWORD, OAUTH2_PROXY_COOKIE_SECRET
# Optionally set CRAWLER_EDC_CLIENT_ID and crawler DB credentials
```

2. (Optional) If you want Postgres to re-run its init SQL, remove the volume first:

```bash
docker compose -f local-deploy/docker-compose.yml down -v
```

3. Start the stack:

```bash
docker compose -f local-deploy/docker-compose.yml up -d
```

4. Import the Keycloak realm and extract client secrets (recommended):

Use the provided helper script to import the realm JSON and fetch client secrets. That will optionally update `local-deploy/.env`.

```bash
cd local-deploy
./scripts/import_realm_and_extract_secrets.sh \
  --kc-url http://localhost:8081 \
  --admin-user "$KEYCLOAK_ADMIN_USERNAME" --admin-pass "$KEYCLOAK_ADMIN_PASSWORD" \
  --realm-json ../authority-portal-backend/authority-portal-quarkus/src/main/resources/realm.json \
  --env-file .env --update-env
```

5. Restart oauth2-proxy so it reads the updated secrets:

```bash
docker compose -f local-deploy/docker-compose.yml up -d oauth2-proxy
```

6. Verify basic endpoints:

```bash
curl -s http://localhost:8081/realms/authority-portal/.well-known/openid-configuration | jq .issuer
docker compose -f local-deploy/docker-compose.yml logs --tail=200 oauth2-proxy
```

## Access URLs (defaults)
- Frontend (via Caddy): http://localhost
- Keycloak admin UI (host-mapped): http://localhost:8081 (host mapping may vary)
- Catalog crawler: http://localhost:11003
- Logging House stub: http://localhost:9200

## Key manual steps after startup
- Import the realm JSON from:
  `authority-portal-backend/authority-portal-quarkus/src/main/resources/realm.json` if you did not run the import script.
- After importing the realm, obtain or regenerate client secrets for:
  - `oauth2-proxy` → set `OAUTH2_PROXY_CLIENT_SECRET` in `.env`
  - `authority-portal-client` → set `AP_CLIENT_SECRET` in `.env`

## Catalog crawler notes
- The catalog crawler needs a reachable Postgres DB and valid credentials for the DAPS/OAuth provider (Keycloak). It will only crawl connectors that are registered and accessible in the same realm.
- Provide crawler-related variables in `.env` (see `.env.sample`): `CRAWLER_EDC_CLIENT_ID`, `CRAWLER_DB_JDBC_URL`, `CRAWLER_DB_JDBC_USER`, `CRAWLER_DB_JDBC_PASSWORD`, `CRAWLER_ENVIRONMENT_ID`, `MY_EDC_FQDN`.

## Logging House
- For local testing a small HTTP stub is provided as a placeholder for the Logging House. Replace it with a real logging-house image if you have one.

## Development vs Production (C → A → B)
- **C (Automate)**: Run `./scripts/import_realm_and_extract_secrets.sh` to import the Keycloak realm and populate client secrets.
- **A (Dev)**: The compose in this folder supports a local HTTP/dev mode where oauth2-proxy may be configured to skip OIDC discovery and use explicit HTTP endpoints for quick testing. This is insecure and only for development.
- **B (Prod/TLS)**: For production, enable TLS, use HTTPS issuer URLs, enable oauth2-proxy discovery, and set secure cookie settings.

## HTTP local dev quickstart
- This repository includes instructions and helpers to run everything over plain HTTP for local testing. The import script updates the realm and secrets and the compose file supports the oauth2-proxy debug/dev flags for HTTP.

## Security caveats
- Do not store client secrets, API keys, or passwords in the repository. Use a secure secret store (Vault, Kubernetes Secrets, environment variables managed per-environment).
- The HTTP flow is for development only. In production always use TLS and set `cookie-secure=true` on oauth2-proxy.

## Troubleshooting
- If oauth2-proxy returns `403` with "HTTPS required", Keycloak is enforcing TLS. Either enable TLS or set the realm's `sslRequired` to `none` (dev only) and/or run oauth2-proxy in skip-discovery mode with explicit endpoints for local testing.
- If containers exit with `exec format error`, your host architecture (e.g. linux/arm64) doesn't match the images' architecture (linux/amd64). Options:
  - Enable QEMU/binfmt emulation so amd64 images run on arm64.
  - Build images locally for your architecture and update `docker-compose.yml` to use `build:` entries.
  - Add `platform: linux/amd64` to service definitions (requires QEMU emulation to work reliably).

## TLS (production guidance)
- Recommended: use Caddy or another TLS terminator as the public entry point and terminate TLS there. Caddy can automatically obtain certificates from Let's Encrypt.

### Pattern 1 — Caddy + Let's Encrypt (recommended)
- Configure DNS so your domain (e.g. `keycloak.example.com`, `portal.example.com`) points to the host running Caddy.
- Use a `Caddyfile` that reverse-proxies to the internal Keycloak and oauth2-proxy services and sets `X-Forwarded-*` headers.
- Set Keycloak's `KC_HOSTNAME` to your public hostname and configure oauth2-proxy to use the HTTPS issuer URL and `cookie-secure=true`.

### Pattern 2 — Local HTTPS with mkcert (development)
- Use `mkcert` to generate locally trusted certificates for hostnames like `keycloak.local` and `portal.local` and mount them into Caddy. Add entries to `/etc/hosts` so these hostnames resolve to `127.0.0.1`.

## Next steps / optional improvements I can help with
- Add a `docker-compose` variant that forces `platform: linux/amd64` or builds arm64 images locally.
- Provide a Caddy + Let's Encrypt production compose example and Caddyfile template.
- Add automation to fully bootstrap the dev environment in one script (import realm, update `.env`, restart oauth2-proxy, smoke tests).

If you want one of these, tell me which and I will implement it.
- Caddy を TLS 終端（リバースプロキシ）に使う想定。Caddy は Let's Encrypt を使った自動発行を行えるため楽です。



