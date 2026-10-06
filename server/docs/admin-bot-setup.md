# Admin bot: server setup

Everything the admin bot needs **outside** `server/admin-bot/`. Plugin development and testing are covered in [../admin-bot/README.md](../admin-bot/README.md), and the design in [../admin-bot/claude.md](../admin-bot/claude.md).

Goal: as few changes to the running system as possible.
- The bot runs in the **existing** maubot container, with no new containers, ports, `.env` variables or changes to `setup.sh`/`create_env.sh`.
- There are four small file changes, plus two later.

Run the same steps on the test node first, then on the ITS VM.

## Overview

| # | Change | File | When | Effect on the running system |
|---|---|---|---|---|
| 1 | Plugin data in Postgres instead of SQLite | `maubot/config.yaml.template` | before the bot's first start | maubot restart (seconds) |
| 2 | Pin the maubot image | `docker-compose.yml` | now | maubot container recreated only if the version changes |
| 3 | Bot data in the backup | `backup.sh`, `restore.sh` | before real data (Phase 1) | none |
| 4 | Signup pages reachable from outside | `nginx/matrix.conf` | before Phase 3 on production (can be merged now) | `nginx -t` + reload, no downtime |
| 5 | Bot account, client, instance | none (manual steps) | Phase 0 | none |
| 6 | Switch off open registration | `homeserver.yaml.template` | **after** Phase 3 works | Synapse restart (seconds) |
| – | Second maubot for professor bots | several | Phase 8, see the end | – |

Changes 1–4 go into one PR; change 6 is a separate, later PR.

---

## 1. Plugin database in Postgres

Today `plugin_databases.postgres` is `null`, so plugins get SQLite files under `server/maubot/plugins/`. `backup.sh` doesn't back those up.

`server/maubot/config.yaml.template`:

```diff
 plugin_databases:
     ...
-    postgres: null
+    postgres: default
```

- `default` reuses the existing `maubot` database. Each plugin instance gets its own Postgres schema there.
- No new database or credentials are needed.
- Plugins already running in this maubot that use the new DB interface start with an empty Postgres schema. Their old SQLite files stay where they are. On our server that only affects test bots.

## 2. Pin the maubot image

`maubot:latest` can change underneath us at any `docker compose pull`. The bot's API calls were checked against maubot **0.6.0**.

First check what is running:

```bash
docker compose exec maubot python3 -c "import maubot; print(maubot.__version__)"
docker manifest inspect dock.mau.dev/maubot/maubot:v0.6.0 >/dev/null && echo "tag exists"
```

`server/docker-compose.yml`:

```diff
   maubot:
-    image: dock.mau.dev/maubot/maubot:latest
+    image: dock.mau.dev/maubot/maubot:v0.6.0
```

- If the running version isn't 0.6.0, pin the version that is running instead and tell whoever works on the bot. `requirements-dev.txt` must use the same version.
- If the tag name differs (check the registry), use the name that `docker manifest inspect` accepts.

## 3. Backups include the bot

`backup.sh` only dumps the Synapse database. Courses, staff, templates and signup tokens live in the `maubot` database.

`server/backup.sh`, after the existing `pg_dump`:

```bash
echo "dumping maubot DB (bots, admin bot state)"
docker compose exec -T postgres pg_dump -U "$POSTGRES_USER" -d maubot --format=custom > "$STAGE_DIR/maubot.dump"
```

`server/restore.sh`, after the Synapse database is restored, before `docker compose start synapse`:

```bash
if [ -f "$STAGE_DIR/maubot.dump" ]; then
  echo "Restoring maubot database"
  docker compose stop maubot
  docker compose exec -T postgres pg_restore -U "$POSTGRES_USER" -d maubot --clean --if-exists < "$STAGE_DIR/maubot.dump"
  docker compose start maubot
fi
```

The `if` keeps old backups (without `maubot.dump`) restorable.

**Note:** the backup now also holds the maubot clients' access tokens, including the admin bot's server-admin token. It already holds Synapse's tokens and password hashes, so treat backups like `.env`.

## 4. Public route for the signup pages

Host nginx sends everything under `/_matrix` to Synapse. maubot only listens on `127.0.0.1:29316`. We expose **only** the bot's webapp prefix. The maubot UI and management API (`/_matrix/maubot/v1/...`) stay unreachable from outside.

`server/nginx/matrix.conf`. At the top of the file, outside `server { }` (the file is included in nginx's `http` block):

```nginx
# Admin bot signup pages: max 10 requests per minute per IP
limit_req_zone $binary_remote_addr zone=adminbot_signup:1m rate=10r/m;
```

Inside the `server { }` block, before the `location ~ ^(/_matrix|...)` block:

```nginx
    # Admin bot signup/reset pages (maubot webapp of the instance "adminbot").
    # ^~ makes this prefix win over the regex location below. Only this prefix:
    # the maubot UI and API stay internal.
    location ^~ /_matrix/maubot/plugin/adminbot/ {
        limit_except GET POST { deny all; }
        limit_req zone=adminbot_signup burst=10 nodelay;
        client_max_body_size 16k;

        proxy_pass http://127.0.0.1:29316;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Host $host;
    }
```

- `29316` is `MAUBOT_UI_PORT` from `.env`. nginx can't read `.env`, so it's hardcoded like `8008` already is.
- The path contains the **instance ID** `adminbot`, so the instance in step 5 must have exactly that ID.
- Safe to merge before the bot exists: maubot answers 404 for unknown instances.

Apply (the vhost is a symlink to the repo file):

```bash
sudo nginx -t && sudo systemctl reload nginx
curl -s -o /dev/null -w '%{http_code}\n' https://matrix.dmi.unibas.ch/_matrix/maubot/v1/version    # expect 404 (Synapse), NOT maubot
curl -s -o /dev/null -w '%{http_code}\n' https://matrix.dmi.unibas.ch/_matrix/maubot/plugin/adminbot/signup   # expect 400/404 from maubot until the bot runs
```

**Test node:** no change needed. Admin nginx (`nginx/admin.conf`) already proxies `/_matrix/maubot/` through the SSH tunnel. Use `https://localhost:8443/_matrix/maubot/plugin/adminbot` as `signup.public_base_url` there.

## Applying 1–4 on a server

```bash
cd /MARVIN/matrix-unibas && git pull
cd server
./setup.sh                        # re-renders maubot/config.yaml; recreates maubot if the image tag changed
docker compose restart maubot     # loads the new maubot config (no-op if it was just recreated)
sudo nginx -t && sudo systemctl reload nginx
docker compose logs --tail 50 maubot   # no errors
```

Re-running `setup.sh` is how config changes are applied in this repo:
- The signing key and certs are skipped because they already exist.
- The other rendered configs come out identical if their templates are unchanged.
- One side effect: maubot's generated `unshared_secret` is replaced, so you have to log in to the maubot UI again.

## 5. Bot account, client and instance (Phase 0)

No file changes. This follows [maubot.md](maubot.md), with these specifics:

1. **Matrix account, as server admin.** The bot needs the admin API:
   ```bash
   docker compose exec synapse register_new_matrix_user -c /data/homeserver.yaml -u adminbot -a http://localhost:8008
   ```
   Store the password in the team password manager. It's only needed for recovery.
2. **maubot client:** `mbc login`, then `mbc auth --update-client` for `adminbot`, as in maubot.md. In the client settings, turn on **autojoin**: the bot must join DMs. It ignores commands anywhere else.
3. **Verify** the client with a recovery key (maubot.md, "Verify the bot account"). Professors' DMs are encrypted.
4. **Plugin:** upload the `.mbp` in the maubot UI.
5. **Instance:** ID **`adminbot`** (fixed, the nginx route uses it), type `ch.unibas.dmi.marvin.adminbot`, primary user `@adminbot:matrix.dmi.unibas.ch`.
6. **Audit room:** create a private room, invite the bot, and copy the room ID (Element: room settings → Advanced).
7. **Instance config** (maubot UI → instance):
   - `admins`: your user IDs
   - `audit_room`: the room ID
   - `signup.public_base_url`: `https://matrix.dmi.unibas.ch/_matrix/maubot/plugin/adminbot` (test node: the tunnel URL above)
   - `signup.login_url`: `https://matrix.dmi.unibas.ch`
8. **Check:**
   - The audit room shows the self-check.
   - A DM `!whoami` to the bot answers with your roles.
   - A non-admin gets no answer.

The bot sets its own Synapse rate-limit exemption at startup, so no manual step is needed for that.

## 6. Switch off open registration (after Phase 3)

Only once signup links work on production. Until then, Ketesa registration tokens are the stopgap for staff and testers.

`server/homeserver.yaml.template`:

```diff
-enable_registration: true
-registration_requires_token: true
+enable_registration: false
```

```bash
./setup.sh && docker compose restart synapse
```

The admin API still creates accounts, both for the bot and for Ketesa. Only self-registration in Element disappears.

---

## Deliberately not changed

These came up in the plan review, but aren't needed and would touch more of the running system:

| Item | Why not now |
|---|---|
| Random `crypto_db_pickle_key` (still `mau.crypto`) | Changing it breaks the crypto sessions of every existing maubot client, so they'd need re-creating and re-verifying. The key sits next to the database on the same host, so it adds little protection. Do it on the next fresh install. |
| Remove `registration_secrets` from the maubot config | The bot doesn't use it, and anyone who can use it already has maubot admin. Remove it together with the userbots setup. |
| `MAUBOT_ADMIN_PASS` duplicate in `.env.example` / `create_env.sh` | Harmless leftover. |
| New `.env` variables, `setup.sh` / `create_env.sh` changes | Not needed until the second maubot (Phase 8). |
| `docs/startup.md` still mentions Ketesa in the stack | Docs only; fix whenever. |

## Rollback

| # | Undo |
|---|---|
| 1 | Revert the template line, `./setup.sh`, `docker compose restart maubot`. The bot's data stays in the Postgres schema, unused. |
| 2 | Revert to `:latest`, `docker compose up -d maubot`. |
| 3 | Revert the scripts. |
| 4 | Revert `matrix.conf`, `sudo nginx -t && sudo systemctl reload nginx`. |
| 5 | Stop/delete the instance in the maubot UI. Deactivate `@adminbot` in Ketesa. |
| 6 | Revert the template, `./setup.sh && docker compose restart synapse`. |

## Later: second maubot for professor bots (Phase 8)

This is the only part that needs bigger changes, so it waits until Phases 0–7 run. Outline (details in the plan, §10 and §16 I7):

- `docker-compose.yml`: new service `userbots` (`container_name: matrix-userbots`), same pinned image, volume `./userbots:/data`, **no `ports:`**.
- `userbots/config.yaml.template`, with:
  - database `.../userbots`
  - `plugin_databases.postgres: default`
  - its own pickle key
  - no `registration_secrets`
  - `admins:` with only `adminbot: ${USERBOTS_ADMIN_PASSWORD}`
  - `api_features` with `client_auth`, `dev_open` and `instance_database` off
- `.env.example` + `create_env.sh`: `USERBOTS_ADMIN_PASSWORD`. `setup.sh`: render the new template, `chown` like `./maubot`, add the variable to `required_vars`.
- `postgres-init.sh` only runs on a fresh volume. On existing servers, once:
  `docker compose exec postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c 'CREATE DATABASE userbots'` (never `down -v`).
- `backup.sh` / `restore.sh`: also `userbots`.
- `.gitignore`: `**/userbots/config.yaml`, `**/userbots/plugins/`, `**/userbots/trash/`.
- Bot instance config: `user_bots.enabled: true`, `maubot_url: http://userbots:29316`, `password`.
