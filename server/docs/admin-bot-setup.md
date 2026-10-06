# Admin bot: server setup

Everything the admin bot needs on the server. The plugin itself (code, development, testing, building the `.mbp`) lives in its own repository, [adminBot](https://github.com/Noah-Klaholz/adminBot): see its `README.md`, and `claude.md` for the design.

Goal: as few changes to the running system as possible.
- Phases 0–7: the bot runs in the **existing** maubot container. No new containers or ports.
- Phase 8 (professor bots) adds one internal container, `userbots`, with no published port.

Run every step on the test node first, then on the ITS VM.

## Overview

| # | Change | Files | When | Effect on the running system |
|---|---|---|---|---|
| 1 | Plugin data in Postgres instead of SQLite | `maubot/config.yaml.template` | before the bot's first start | maubot restart (seconds) |
| 2 | Pin the maubot image | `docker-compose.yml`, `.env` (`MAUBOT_IMAGE_TAG`) | before the bot's first start | maubot recreated only if the version changes |
| 3 | Bot data in the backup | `backup.sh`, `restore.sh` | before real data (Phase 1) | none |
| 4 | Signup pages reachable from outside | `nginx/matrix.conf` | before Phase 3 on production | `nginx -t` + reload, no downtime |
| 5 | Bot account, client, instance | none (manual steps) | Phase 0 | none |
| 6 | Switch off open registration | `homeserver.yaml.template` | **after** Phase 3 works | Synapse restart (seconds) |
| 7 | Second maubot for professor bots | compose, `userbots/config.yaml.template`, `setup.sh`, `.env`, `create_env.sh`, `postgres-init.sh`, backup scripts, `.gitignore` | Phase 8 | one new container, others untouched |

Changes 1–4 and 7 are in the repo. 6 is a separate, later change.

On a **fresh install** (`create_env.sh` + `setup.sh` on an empty server) 1–3 and 7 come with the repo, and only the manual steps (5, 7.4) and the checks are needed. The sections below also cover upgrading a running server.

---

## 1. Plugin database in Postgres

`server/maubot/config.yaml.template`:

```yaml
plugin_databases:
    postgres: default
```

- `default` reuses the existing `maubot` database. Each plugin instance gets its own Postgres schema there.
- Before this change it was `null`: plugins got SQLite files under `server/maubot/plugins/`, which `backup.sh` doesn't back up.
- Plugins that were already running and use the new DB interface start with an empty Postgres schema. Their old SQLite files stay where they are. On our server that only affected test bots.

## 2. Pin the maubot image

`maubot:latest` can change underneath us at any `docker compose pull`. The bot's API calls were checked against maubot **0.6.0**.

`docker-compose.yml` uses `dock.mau.dev/maubot/maubot:${MAUBOT_IMAGE_TAG}` for both maubot containers, and `setup.sh` refuses to run without the variable. In `.env`:

```bash
MAUBOT_IMAGE_TAG=v0.6.0
```

Check what is running and that the tag exists:

```bash
docker compose exec maubot python3 -c "import maubot; print(maubot.__version__)"
docker manifest inspect dock.mau.dev/maubot/maubot:v0.6.0 >/dev/null && echo "tag exists"
```

- If the running version isn't 0.6.0, pin the version that is running and tell whoever works on the bot. The bot repo's `requirements-dev.txt` must use the same version.
- Both maubots must always use the same tag: the admin bot rejects professor plugins whose Python dependencies are missing from *its own* image.

## 3. Backups include the bot

`backup.sh` dumps, next to the Synapse database:
- the `maubot` database (courses, staff, templates, signup tokens, the admin bot's config and access token)
- once Phase 8 is set up: the `userbots` database and the files in `userbots/plugins/` (the only copy of professors' plugins; the admin bot deletes its copy after provisioning). This part is skipped while the `userbots` database doesn't exist.

`restore.sh` restores each part only if the backup contains it, so older backups stay restorable.

**Note:** backups now hold the maubot clients' access tokens, including the admin bot's server-admin token. They already held Synapse's tokens and password hashes, so treat backups like `.env`.

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
- maubot answers 404 for unknown instances, so the route is harmless before the bot exists.

Apply (the vhost is a symlink to the repo file):

```bash
sudo nginx -t && sudo systemctl reload nginx
curl -s -o /dev/null -w '%{http_code}\n' https://matrix.dmi.unibas.ch/_matrix/maubot/v1/version    # expect 404 (Synapse), NOT maubot
curl -s -o /dev/null -w '%{http_code}\n' https://matrix.dmi.unibas.ch/_matrix/maubot/plugin/adminbot/signup   # expect 400/404 from maubot, not Synapse
```

**Test node:** no change needed. Admin nginx (`nginx/admin.conf`) already proxies `/_matrix/maubot/` through the SSH tunnel. Use `https://localhost:8443/_matrix/maubot/plugin/adminbot` as `signup.public_base_url` there.

## Applying 1–4 on a server

```bash
cd /MARVIN/matrix-unibas && git pull     # "unable to unlink ... Permission denied": see Troubleshooting
cd server
grep -q '^MAUBOT_IMAGE_TAG=' .env || echo 'MAUBOT_IMAGE_TAG=v0.6.0' >> .env
./backup.sh
./setup.sh                        # re-renders the configs; recreates maubot if the image tag changed
docker compose restart maubot     # loads the new maubot config (no-op if it was just recreated)
sudo nginx -t && sudo systemctl reload nginx
docker compose logs --tail 50 maubot   # no errors
```

Re-running `setup.sh` is how config changes are applied in this repo:
- The signing key and certs are skipped because they already exist.
- The other rendered configs come out identical if their templates are unchanged.
- One side effect: maubot's generated `unshared_secret` is replaced, so you have to log in to the maubot UI again. (The admin bot logs in to `userbots` again on its own.)

## 5. Bot account, client and instance (Phase 0)

No file changes. This follows [maubot.md](maubot.md), with these specifics:

1. **Matrix account, as server admin.** The bot needs the admin API:
   ```bash
   docker compose exec synapse register_new_matrix_user -c /data/homeserver.yaml -u adminbot -a http://localhost:8008
   ```
   Store the password in the team password manager. It's only needed for recovery.
2. **maubot client:** `mbc login`, then `mbc auth --update-client` for `adminbot`, as in maubot.md. In the client settings, turn on **autojoin**: the bot must join DMs. It ignores commands anywhere else.
3. **Verify** the client with a recovery key (maubot.md, "Verify the bot account"). Professors' DMs are encrypted.
4. **Plugin:** upload the `.mbp` in the maubot UI (built as described in the bot repo's README).
5. **Instance:** ID **`adminbot`** (fixed, the nginx route uses it), type `ch.unibas.dmi.marvin.adminbot`, primary user `@adminbot:matrix.dmi.unibas.ch`.
6. **Audit room:** create a private room, invite the bot, and copy the room ID (Element: room settings → Advanced).
7. **Instance config** (maubot UI → instance):
   ```yaml
   admins:
     - "@your.name:matrix.dmi.unibas.ch"   # full Matrix ID, in quotes
   audit_room: "!roomid:matrix.dmi.unibas.ch"
   signup:
     public_base_url: https://matrix.dmi.unibas.ch/_matrix/maubot/plugin/adminbot   # test node: the tunnel URL above
     login_url: https://matrix.dmi.unibas.ch
   ```
   - `admins` (and `professors`) take **full Matrix IDs**. A bare localpart like `noah` never matches, and the bot silently ignores that user.
   - Quote every value that starts with `@` or `!`. In YAML both are reserved at the start of a plain value, so unquoted they are a parse error.
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

## 7. Professor bots: second maubot "userbots" (Phase 8)

Professors upload a plugin (`.mbp`) to the admin bot. After an admin approves it, the admin bot creates the Matrix account, the maubot client and the instance by itself. Design and reasoning: bot repo `claude.md` §10.

**Why a second maubot:** maubot plugins run unsandboxed in the maubot process and can read every client's access token. A professor plugin in the main maubot could take the admin bot's server-admin token. So professor bots run in `userbots`:
- its own container (`matrix-userbots`) and database (`userbots`)
- **no published port**: only the admin bot reaches it, over the Docker network at `http://userbots:29316`
- one login, `adminbot`, used only by the admin bot
- no `registration_secrets`; `client_auth`, `client_proxy`, `dev_open`, `instance_database` and `log` are off
- its own crypto pickle key

The admin bot refuses to provision bots if `user_bots.maubot_url` points at the maubot it runs in.

### 7.1 What is in the repo

| File | Content |
|---|---|
| `docker-compose.yml` | service `userbots`: same `${MAUBOT_IMAGE_TAG}`, volume `./userbots:/data`, no `ports:` |
| `userbots/config.yaml.template` | database `.../userbots`, `plugin_databases.postgres: default`, pickle key `${USERBOTS_CRYPTO_PICKLE_KEY}`, `admins: adminbot: ${USERBOTS_ADMIN_PASSWORD}`, the API switches above |
| `.env.example`, `create_env.sh` | `USERBOTS_ADMIN_PASSWORD`, `USERBOTS_CRYPTO_PICKLE_KEY` (generated for new `.env` files) |
| `setup.sh` | requires both variables, renders `userbots/config.yaml`, `chown 1337` |
| `postgres-init.sh` | creates the `userbots` database, **only on a fresh Postgres volume** |
| `backup.sh`, `restore.sh` | `userbots` database + plugin files (section 3) |
| `.gitignore` | `**/userbots/config.yaml`, `**/userbots/plugins/`, `**/userbots/trash/` |

### 7.2 Roll out on a running server

```bash
cd /MARVIN/matrix-unibas && git pull     # "unable to unlink ... Permission denied": see Troubleshooting
cd server

# 1. Secrets. create_env.sh won't touch an existing .env, so append them once:
grep -q '^USERBOTS_ADMIN_PASSWORD=' .env    || echo "USERBOTS_ADMIN_PASSWORD=$(openssl rand -hex 32)" >> .env
grep -q '^USERBOTS_CRYPTO_PICKLE_KEY=' .env || echo "USERBOTS_CRYPTO_PICKLE_KEY=$(openssl rand -hex 32)" >> .env

# 2. Backup (skips the userbots part, the database doesn't exist yet)
./backup.sh

# 3. Database. Must exist BEFORE the container starts. Never `docker compose down -v`.
set -a; source .env; set +a
docker compose exec postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c 'CREATE DATABASE userbots'

# 4. Render the config and start the new container (the others stay as they are)
./setup.sh
docker compose logs --tail 50 userbots    # no errors
```

Never change `USERBOTS_CRYPTO_PICKLE_KEY` after the first start: it would break the crypto sessions of every professor bot.

### 7.3 Check isolation and login

```bash
docker port matrix-userbots     # must print NOTHING (no published port)

# login as the admin bot will do it, from inside the maubot container; expect: 200 True
set -a; source .env; set +a
docker compose exec -e PW="$USERBOTS_ADMIN_PASSWORD" maubot python3 -c "import json,os,urllib.request as u; r=u.urlopen(u.Request('http://userbots:29316/_matrix/maubot/v1/auth/login', json.dumps({'username':'adminbot','password':os.environ['PW']}).encode(), {'Content-Type':'application/json'})); print(r.status, 'token' in json.load(r))"
```

A `401` here means the name or password doesn't match (see Troubleshooting). A `URLError` means the container isn't running or not on the same Docker network. Note that `GET /_matrix/maubot/v1/version` also answers 401 without a login, so it doesn't show whether login works.

### 7.4 Turn it on in the admin bot

maubot UI → instance `adminbot` → config:

```yaml
user_bots:
  enabled: true
  maubot_url: http://userbots:29316
  username: adminbot
  password: "<USERBOTS_ADMIN_PASSWORD from .env>"   # in quotes: a hex string can be read as a number
  homeserver_url: http://synapse:8008
  require_approval: true
  max_per_professor: 3
  max_mbp_size_mb: 10
  ratelimit_exempt: false
```

Saving re-runs the self-check. A passing `userbots` check is **silent**. Only failures are posted to the audit room:
- "points at THIS maubot – refusing": `maubot_url` is wrong.
- `login failed`: the password doesn't match `.env`.
- connection error: the container isn't running.

The password is stored in the instance config, so it ends up in the `maubot` backup too.

### 7.5 End-to-end test

Test with a **non-admin** professor. Requests from admins are approved automatically, so the approval step would be skipped.

1. Build a test plugin on your laptop (`mbc` is in the bot repo's venv):
   ```bash
   git clone https://github.com/maubot/echo && cd echo && <bot-repo>/.venv/bin/mbc build
   ```
2. Create a test account (Ketesa or a signup link), then as admin: `!admin prof add @test.prof:matrix.dmi.unibas.ch`.
3. As the professor, in a DM with the bot: `!bot create echo`, then send the `.mbp`.
4. The request appears in the audit room. As admin: `!admin bots pending`, then `!admin bots approve <id>`.
5. The professor gets "Your bot **echo** is running as `@bot.test.prof.echo:…`". Invite it to a room and send `!ping`. Also try an encrypted room.
6. As the professor: `!bot list`, `!bot info echo`, `!bot stop echo`, `!bot start echo`.
7. `!bot delete echo`. Afterwards the account is deactivated and the plugin is gone:
   ```bash
   docker compose exec userbots ls /data/plugins
   ```
8. As admin: `!admin bots disable-all` (kill switch; stops every professor bot).
9. `./backup.sh` now also prints "dumping userbots DB + plugin files".

### 7.6 Running it

| Task | How |
|---|---|
| Pending requests | posted to the audit room; `!admin bots pending`, `approve <id>`, `reject <id> [reason]` |
| Stop all professor bots now | `!admin bots disable-all` |
| Switch the feature off | `user_bots.enabled: false` in the admin bot config; bot commands are refused |
| Logs | `docker compose logs -f userbots` (there is no UI for this maubot) |
| maubot update | change `MAUBOT_IMAGE_TAG`, `./setup.sh`; both maubots move together |

Remaining risk: professor bots share one process with each other, so a malicious plugin could read another professor bot's token. Those are unprivileged accounts. Approval, the quota and the kill switch are the mitigations.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `!whoami` gets no answer | `admins` holds a localpart instead of the full Matrix ID | `- "@name:matrix.dmi.unibas.ch"` (quoted), see 5.7 |
| `git pull`: `unable to unlink old 'server/userbots/config.yaml.template': Permission denied` | `setup.sh` (and the container) give `server/maubot/` and `server/userbots/` to uid 1337, and the templates live inside them | `sudo chown "$(id -u):$(id -g)" server/maubot server/userbots server/*/config.yaml.template`, then `git status` (restore a half-updated file with `git checkout -- <file>`) and `git pull` again. `setup.sh` hands the folders back to 1337. |
| `backup.sh`: database "userbots" does not exist | old `backup.sh` | pull; the current one skips userbots until the database exists |
| Login test (7.3) gives 401 | `.env` not loaded in your shell (`echo ${#USERBOTS_ADMIN_PASSWORD}` must print 64), or `userbots/config.yaml` rendered before the variable existed | `./setup.sh && docker compose restart userbots`. `sudo grep -A2 '^admins:' userbots/config.yaml` must show `adminbot: $2b$...` (maubot hashes the password at startup). |
| userbots keeps restarting | database `userbots` missing | 7.2 step 3 |

---

## Deliberately not changed

These came up in the plan review, but aren't needed and would touch more of the running system:

| Item | Why not now |
|---|---|
| Random `crypto_db_pickle_key` in the **main** maubot (still `mau.crypto`) | Changing it breaks the crypto sessions of every existing maubot client, so they'd need re-creating and re-verifying. The key sits next to the database on the same host, so it adds little protection. Do it on the next fresh install. (`userbots` has its own random key.) |
| Remove `registration_secrets` from the main maubot config | The bot doesn't use it, and anyone who can use it already has maubot admin. (`userbots` has none.) |
| `MAUBOT_ADMIN_PASS` duplicate in `.env.example` / `create_env.sh` | Harmless leftover. |

## Rollback

| # | Undo |
|---|---|
| 1 | Revert the template line, `./setup.sh`, `docker compose restart maubot`. The bot's data stays in the Postgres schema, unused. |
| 2 | Set `MAUBOT_IMAGE_TAG` to the previous tag, `./setup.sh`. |
| 3 | Revert the scripts. |
| 4 | Revert `matrix.conf`, `sudo nginx -t && sudo systemctl reload nginx`. |
| 5 | Stop/delete the instance in the maubot UI. Deactivate `@adminbot` in Ketesa. |
| 6 | Revert the template, `./setup.sh && docker compose restart synapse`. |
| 7 | `!admin bots disable-all`, `user_bots.enabled: false`, `docker compose stop userbots`. Removing it completely: revert the repo changes and `docker compose up -d --remove-orphans`. The `userbots` database stays, unused. |
