# MARVIN — First Test Deployment on the ITS Server

> **Status: planned steps to deploy — a proposal, not a decision.**
> This document was drafted with an AI assistant (Claude, via Claude Code) and
> is meant as a starting point for team discussion. The project maintainers
> (Noah Klaholz, Chris Jacomet, Vincent Schall) decide what is actually done,
> and in which order. Anything here may change once we have access to the ITS
> server.

This manual takes the team from the current repo state to a first working
Synapse on the ITS-managed VM, and then outlines the final goal: deploying with
Ansible. **Out of scope:** Switch edu-ID / SSO, Element Web, mautrix-discord,
Coturn, Prometheus/Grafana. Those come after this works.

| | |
|---|---|
| VM (host FQDN) | `dmi-matrix.dmi.unibas.ch` |
| Matrix server name (service FQDN) | `matrix.dmi.unibas.ch` |
| Managed by ITS | OS, Nginx, Let's Encrypt, (host) Postgres, Docker |
| Managed by us | everything in this repo, the `.env`, the containers |
| ITS ticket | #23866 (RO-035) |

> **The server name is permanent.** Every user ID (`@alice:matrix.dmi.unibas.ch`)
> and the server's signing key depend on it. If it is wrong, the only fix is
> wiping the server (see [Reset](#reset-wipe-the-test-deployment)). This is a
> test deploy, so wiping is acceptable — but only until real users join.

> **The repo is public.** Never commit `.env`, rendered configs, keys or
> backups (the `.gitignore` covers them). Never paste secrets into GitHub
> issues, PRs or chat.

---

## Overview

1. [Prepare the repo](#1-prepare-the-repo) — on a laptop, one PR
2. [Inspect the server](#2-inspect-the-server) — first SSH login, decide on Postgres
3. [Ask ITS for what's missing](#3-ask-its-for-whats-missing) — Nginx vhost, access
4. [Install](#4-install) — clone, `.env`, `setup.sh`
5. [Create the first users](#5-create-the-first-users)
6. [Verify](#6-verify)
7. [Final goal: deploy with Ansible](#7-final-goal-deploy-with-ansible) — replaces `setup.sh`

---

## 1. Prepare the repo

Do this on a laptop, as one PR, **before** the first pull on the server.

### 1.1 Rename the stack folder

```bash
git mv test_synaps server
```

All paths below use `server/`.

### 1.2 Pin the Compose project name

The Docker volume for Postgres is named after the Compose project, which
defaults to the folder name. Pin it so a future folder rename can't make the
database "disappear". At the very top of `server/docker-compose.yml`:

```yaml
name: marvin

services:
  ...
```

### 1.3 Bind ports to localhost only

The ITS Nginx on the same VM is the only thing that should talk to Synapse.
Maubot's UI is reached through the admin tunnel. In `server/docker-compose.yml`:

```yaml
  synapse:
    ports:
      - "127.0.0.1:${SYNAPSE_HTTP_PORT}:8008"

  maubot:
    ports:
      - "127.0.0.1:${MAUBOT_UI_PORT}:29316"
```

### 1.4 Fix `setup.sh`

- Create the cert folder before `openssl` runs (a fresh clone has no
  `nginx/certs/`, so the script currently aborts there):

  ```bash
  mkdir -p "$DATA_DIR" "$CERT_DIR"
  ```

- Add `MAUBOT_UI_PORT` to `required_vars`.
- Optional: in the closing hint, replace the `psql UPDATE users SET admin = 1`
  step with the `-a` flag of `register_new_matrix_user` (see step 5).

### 1.5 Fix the Synapse template

In `server/homeserver.yaml.template`, below `server_name`:

```yaml
public_baseurl: "https://${SERVER_NAME}/"
serve_server_wellknown: true
```

`serve_server_wellknown` lets Synapse answer `/.well-known/matrix/server`
itself, so other servers reach us on port 443 and ITS doesn't need to open 8448.

### 1.6 Fix the Maubot template

In `server/maubot/config.yaml.template`, the domain is hard-coded as
`dmi.matrix.unibas.ch` (wrong — it's `matrix.dmi.unibas.ch`). Replace both
occurrences (`homeservers:` and `registration_secrets:`) with `${SERVER_NAME}`,
and set:

```yaml
    public_url: https://localhost:${ADMIN_UI_PORT}
```

### 1.7 Add `server/.env.example`

`setup.sh` tells people to copy this file, but it doesn't exist yet.
Placeholders only — no real values:

```bash
# Matrix server name — PERMANENT, see docs/deployment.md
SERVER_NAME=matrix.dmi.unibas.ch

# Synapse
SYNAPSE_IMAGE_TAG=vX.Y.Z              # pin a release, never "latest"
SYNAPSE_HTTP_PORT=8008
SYNAPSE_REPORT_STATS=no
SYNAPSE_REGISTRATION_SHARED_SECRET=change-me
SYNAPSE_MACAROON_SECRET_KEY=change-me
SYNAPSE_FORM_SECRET=change-me

# Postgres
POSTGRES_DB=synapse
POSTGRES_USER=synapse
POSTGRES_PASSWORD=change-me

# Admin UI (reached via SSH tunnel only)
ADMIN_UI_PORT=8443

# Maubot
MAUBOT_UI_PORT=29316
MAUBOT_ADMIN_PASSWORD=change-me
```

Check the `.gitignore` still lets it through: `git check-ignore server/.env.example`
must print nothing.

### 1.8 Update the old docs

`server/docs/startup.md` refers to a container called `synapse-test` and the
old test IP. Replace its contents with a link to this manual.

Merge the PR to `main`.

---

## 2. Inspect the server

First SSH login. Goal: find out what ITS set up, and write the answers down
(e.g. in `Journal.md`).

```bash
ssh <unibas-user>@dmi-matrix.dmi.unibas.ch     # from uni network or VPN
```

Run and note the output:

```bash
# System
cat /etc/os-release; nproc; free -h; df -h

# Our permissions
groups                        # is "docker" listed?
sudo -l                       # can we sudo? (setup.sh needs it for chown)

# Tools setup.sh needs
docker version && docker compose version
which git envsubst openssl curl rsync

# What ITS runs
systemctl status nginx postgresql --no-pager
ls /etc/nginx/sites-enabled /etc/nginx/conf.d 2>/dev/null
sudo ss -tlnp                 # ports in use — 8008, 8443, 29316 must be free

# Network
curl -sI https://github.com | head -1
getent hosts matrix.dmi.unibas.ch    # DNS for the service name set?
```

### Decision: which Postgres?

| Option | When | What changes |
|---|---|---|
| **A — Postgres in Docker** (current setup) | Default for the first test deploy | Nothing. `backup.sh`/`restore.sh` work as is. |
| **B — ITS host Postgres** | Later, if ITS confirms DB creation, access from Docker and backups | Synapse points at the host DB, `postgres` container removed, backup scripts adapted. |

**Use option A for this test deploy.** It works today and doesn't block on
ITS. Switching to B later means a wipe or a `pg_dump`/`pg_restore` — fine while
it's still a test. If you do go for B, Synapse **requires** the database to be
created with:

```sql
CREATE DATABASE synapse ENCODING 'UTF8' LC_COLLATE='C' LC_CTYPE='C' TEMPLATE template0 OWNER synapse;
```

### Missing tools?

If something from the list above is missing and you have sudo:

```bash
sudo apt install -y git curl rsync openssl gettext-base   # gettext-base = envsubst
```

On a managed VM, ask ITS first before installing packages yourself.

---

## 3. Ask ITS for what's missing

One email / ticket reply covering everything that came up in step 2. Always
needed:

**Nginx vhost for `matrix.dmi.unibas.ch`** (with their Let's Encrypt cert),
forwarding to our Synapse:

```nginx
location ~ ^(/_matrix|/_synapse/client|/\.well-known/matrix) {
    proxy_pass http://127.0.0.1:8008;
    proxy_set_header X-Forwarded-For $remote_addr;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header Host $host;
    proxy_http_version 1.1;
    client_max_body_size 50M;
}
```

Everything else on that host can return 404 for now. **Do not** forward
`/_synapse/admin` — the admin API stays reachable only via the SSH tunnel.

Also ask, if not already answered by step 2:

- Is port 443 on `matrix.dmi.unibas.ch` reachable from the internet, or only
  inside the uni network? (Federation and off-campus clients need the internet.)
- Docker group membership / sudo for all three of us.
- Who else gets SSH access (all team members).

You can start step 4 before the vhost is live — Synapse will just only be
reachable on the VM itself until then.

---

## 4. Install

On the VM, as your own user.

### 4.1 Clone

The repo is public, so plain HTTPS works:

```bash
cd ~          # or a path ITS prefers, e.g. /opt — ask if unsure
git clone https://github.com/matrix-unibas/matrix-unibas.git
cd matrix-unibas/server
```

### 4.2 Create `.env`

```bash
cp .env.example .env
chmod 600 .env
```

Generate one secret per line and paste them into `.env`:

```bash
for v in POSTGRES_PASSWORD SYNAPSE_REGISTRATION_SHARED_SECRET \
         SYNAPSE_MACAROON_SECRET_KEY SYNAPSE_FORM_SECRET MAUBOT_ADMIN_PASSWORD; do
  echo "$v=$(openssl rand -hex 32)"
done
```

Then edit the rest:

```bash
nano .env
```

- `SERVER_NAME=matrix.dmi.unibas.ch` — **double-check spelling.**
- `SYNAPSE_IMAGE_TAG` — the newest release from
  <https://github.com/element-hq/synapse/releases>, e.g. `v1.xxx.0`.

**Store a copy of the finished `.env` in a password manager** the whole team
can reach. Without it (and the signing key), backups cannot be restored.

### 4.3 Run setup

```bash
./setup.sh
```

What it does, in order:

1. Checks `.env` is complete.
2. Creates `data/` and generates the signing key (first run only).
3. Renders `data/homeserver.yaml`, `admin/config.json`, `maubot/config.yaml`
   from the templates.
4. Generates a self-signed cert for the admin UI (first run only).
5. Starts all containers and waits for Postgres and Synapse.

It asks for your sudo password once (Maubot folder ownership).

**Re-running is safe.** It keeps the signing key and cert and re-renders the
configs, so after changing a template or `.env`, just run it again.

### 4.4 Check the containers

```bash
docker compose ps                       # all "running" / "healthy"
docker compose logs -f synapse          # Ctrl+C to leave
curl -s http://127.0.0.1:8008/health    # → OK
```

---

## 5. Create the first users

Registration is on but requires a token, so nobody can sign up on their own.

### 5.1 Admin account (one per team member)

```bash
docker compose exec synapse register_new_matrix_user \
  -c /data/homeserver.yaml -a http://localhost:8008
```

`-a` makes the user a server admin directly. Pick a strong password.

### 5.2 Admin UI

From your laptop, open a tunnel:

```bash
ssh -L 8443:localhost:8443 <unibas-user>@dmi-matrix.dmi.unibas.ch
```

Then browse to <https://localhost:8443> (accept the self-signed cert warning)
and log in with the admin account from 5.1, homeserver `https://localhost:8443`.

From here you can create **registration tokens** (to let test users sign up
themselves), manage users and rooms.

Maubot's UI is on the same tunnel at <https://localhost:8443/_matrix/maubot/>
(user `admin`, password `MAUBOT_ADMIN_PASSWORD` from `.env`).

> **Before edu-ID is set up, only invite the team and a few test users.**
> Accounts created with passwords now are hard to link to edu-ID later.

---

## 6. Verify

Once ITS has the Nginx vhost live:

| Check | How | Expected |
|---|---|---|
| Client API reachable | `curl https://matrix.dmi.unibas.ch/_matrix/client/versions` | JSON with `versions` |
| Server well-known | `curl https://matrix.dmi.unibas.ch/.well-known/matrix/server` | `{"m.server":"matrix.dmi.unibas.ch:443"}` |
| Admin API **not** public | `curl -o /dev/null -w '%{http_code}\n' https://matrix.dmi.unibas.ch/_synapse/admin/v1/server_version` | `404` |
| Login with a client | Element (app or <https://app.element.io>) → *Edit* homeserver → `matrix.dmi.unibas.ch` | Login works |
| Messages | Two test accounts, create a room, chat, send an image | Works, image shows |
| Federation (if internet-reachable) | <https://federationtester.matrix.org> with `matrix.dmi.unibas.ch` | All green |
| Off-campus | Try login from mobile data, not uni Wi-Fi | Works (only if ITS opened it) |

Write the results into `Journal.md`. When everything is green, the first test
deploy is done.

---

## 7. Final goal: deploy with Ansible

`setup.sh` gets us to a first test deploy. The goal is to replace it with an
Ansible playbook. That way the whole server setup is described in the repo, can
be repeated on a fresh VM and is the same no matter which of us runs it. It also
fits how ITS already manages this VM (with Ansible roles).

This is an outline to discuss, not a finished design.

### What the playbook would do

| Today (`setup.sh`) | With Ansible |
|---|---|
| Checks `.env` by hand | Variables in `group_vars/`, and the play fails early if one is missing |
| `envsubst` renders the templates | `template` module with Jinja2 (`homeserver.yaml.j2`, …) |
| Secrets in a `.env` file on the server | Secrets in an `ansible-vault` file, kept **outside** this public repo |
| `sudo chown` for Maubot | `file` module with owner/group |
| `docker compose up -d` | `community.docker.docker_compose_v2` |
| Re-run everything after each change | Only changed configs are applied, and a handler restarts the affected container |
| Signing key generated on first run | Same, guarded with `creates:` so it happens only once |

### Possible layout

```
ansible/
  inventory.yml            # dmi-matrix.dmi.unibas.ch
  group_vars/all.yml       # non-secret settings (server name, ports, image tags)
  site.yml                 # the main playbook
  roles/
    synapse/               # templates, signing key, compose service
    maubot/
    admin_ui/
```

Deploying from a laptop would then be:

```bash
ansible-playbook -i ansible/inventory.yml ansible/site.yml --ask-vault-pass
```

### Open questions (for ITS and the team)

- **ITS's Ansible:** should our playbook stand alone, or plug into their roles
  and inventory? Either way it must not change what ITS manages (Nginx,
  Let's Encrypt, host Postgres), or the two setups will overwrite each other.
- **Where the vault file lives:** a private repo, a password manager or a
  shared drive. The repo is public, so an encrypted vault in it is possible but
  not recommended.
- **Who runs deploys:** only from maintainers' laptops, or later automatically
  from CI (GitHub Actions would need an SSH key for the VM).
- **When to switch:** after the first test deploy works with `setup.sh`, so we
  know what the playbook has to reproduce.

---

## Day-to-day

```bash
cd ~/matrix-unibas/server

git pull && ./setup.sh             # deploy repo changes
docker compose logs -f synapse     # logs
docker compose restart synapse     # restart one service
docker compose down                # stop everything (data stays)
```

Updating Synapse: change `SYNAPSE_IMAGE_TAG` in `.env`, read the release notes
for breaking changes, run `./backup.sh`, then `./setup.sh`.

---

## Reset: wipe the test deployment

Only while it's a test. **Deletes all users, rooms and media.**

```bash
cd ~/matrix-unibas/server
docker compose down -v             # -v deletes the Postgres volume
sudo rm -rf data maubot/config.yaml maubot/plugins maubot/trash maubot/*.log* \
            admin/config.json nginx/certs
./setup.sh                         # fresh start, new signing key
```

`.env` is kept. If you changed `SERVER_NAME`, this is the way to apply it.

---

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `setup.sh`: `Missing .env` | Step 4.2 not done, or run from the wrong folder |
| `setup.sh`: `X is not set` | Missing line in `.env` — compare with `.env.example` |
| `permission denied ... docker.sock` | Not in the `docker` group — log out/in after being added, or ask ITS |
| `setup.sh` stuck at "Waiting for Synapse" | Synapse crashed: `docker compose logs synapse` |
| Synapse log: `Database has incorrect collation` | Host Postgres created without `LC_COLLATE='C'` (option B only) |
| `502 Bad Gateway` from the public URL | Synapse not running, or ITS Nginx forwards to the wrong port |
| Admin UI: connection refused | SSH tunnel not open, or `nginx-admin` container down |
| Element: "homeserver not found" | Nginx vhost missing `/.well-known/matrix`, or DNS not set |
