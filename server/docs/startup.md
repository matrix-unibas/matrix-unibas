# Starting the Server
 
## Prerequisites
- Docker and Docker Compose installed
- User in the `docker` group (or `sudo` privileges)
- Required utilities installed: `git`, `openssl`, `envsubst` (gettext-base), `curl`

## 1. Configure Environment
From the `server/` directory, generate a new `.env` file or create one manually:

```bash
cd server
./create_env.sh
```
Verify the settings inside `.env` (such as `SERVER_NAME`, passwords, and port configurations).

## 2. Initialize and Start the Stack
Run the setup script to generate keys, render templates, and start the containers:

```bash
./setup.sh
```

This will:
1. Verify required environment variables
2. Bootstrap the Synapse signing key (on first run)
3. Render `data/homeserver.yaml`, `admin/config.json`, and `maubot/config.yaml` from templates
4. Generate self-signed certificates for the internal admin UI
5. Start Postgres, Synapse, Ketesa (synapse-admin), Admin Nginx, and Maubot

## 3. Verify Services
Check container status:
```bash
docker compose ps
curl -sf http://localhost:8008/health   # Should return OK
```

## 4. Create the First Admin User
```bash
docker compose exec synapse register_new_matrix_user \
  -c /data/homeserver.yaml -a http://localhost:8008
```

## 5. Access Management UIs
Tunnel port 8443 from your local machine to the server:
```bash
ssh -L 8443:localhost:8443 <unibas-user>@<server-address>
```
- **Admin UI (Ketesa):** `https://localhost:8443`
- **Maubot UI:** `https://localhost:8443/_matrix/maubot/`
