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
Verify the settings inside `.env` (such as `SERVER_NAME`, image tags and ports). All secrets are generated.

## 2. Initialize and Start the Stack
Run the setup script to generate keys, render templates, and start the containers:

```bash
./setup.sh
```

This will:
1. Verify required environment variables
2. Bootstrap the Synapse signing key (on first run)
3. Render `data/homeserver.yaml`, `admin/config.json`, `coturn/turnserver.conf`, `maubot/config.yaml` and `userbots/config.yaml` from templates
4. Generate self-signed certificates for the internal admin nginx
5. Start Postgres, Synapse, Element Web, Admin Nginx, Maubot, Userbots (second maubot for professor bots, internal only) and Coturn

Element Web is served at `https://matrix.dmi.unibas.ch/` by the host nginx. Its config is the static `element/config.json`.

`setup.sh` is also how config changes are applied later: change the template or `.env`, re-run it, restart the affected container.

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
- **Admin UI (Ketesa):** runs locally on your laptop, not on the server, see [admin_ui.md](admin_ui.md).
- **Maubot UI:** through an SSH tunnel, see [maubot.md](maubot.md):
  ```bash
  ssh -L 8443:localhost:8443 <unibas-user>@<server-address>
  ```
  then `https://localhost:8443/_matrix/maubot/`. The `userbots` maubot has no UI; the admin bot manages it.

## 6. Admin bot
Bot account, signup pages and professor bots: [admin-bot-setup.md](admin-bot-setup.md).
