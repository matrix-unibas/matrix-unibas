# Journal

## 24.07.2026 - nkl, cj, vs

We looked through the Matrix.org website to compare the options for servers and found out there are so called "Distributions" now too. Those are essentially pre-packaged playbooks (e.g. Ansible) to have a Quick-Start into self-hosting your server. 
After looking through the options we decided to use Synapse Community and try out the recommended deployment script to get an idea of how those would work: https://github.com/spantaleev/matrix-docker-ansible-deploy/tree/master.
However this did not work out, as a domain and access to DNS settings are a prerequisite to this.
We now decided to switch approaches and try only installing a Synapse Server manually for now and get that to work first.

Next Steps:
- Install and configure a Synapse server manually
- Figure out a way to deploy a web-client without DNS/Domain or get access to a domain -> ask Martin on Monday
- Add other services 
- Write a playbook for easy deployment

## 27.07.2026 - cj

We set up a `test_synapse` folder in the repo to get hands-on experience with configuring and running Synapse before committing to a full deployment approach. Rather than using the Ansible playbook or a pre-packaged distribution, we installed Synapse manually via Docker Compose, using SQLite as the backend since this is only meant for testing configuration, not for production data.
 
We wrote a `setup.sh` script that generates the `homeserver.yaml` config on first run and brings the server up via `docker compose`. Data is kept in a bind-mounted `./data` folder, so stopping and restarting the server does not wipe accounts or config.
 
To test the setup, we created a user via `register_new_matrix_user` inside the running container and connected to it from Element, using the server's IP address directly (`http://<server-ip>:8008`) instead of a domain name, since we don't have DNS access for this test server. This works fine for the client-server connection, but it did surface a real limitation. Without a resolvable `server_name`, things like federation and browser-based Element don't work properly(Theory!). Native clients (Element Desktop) connect without issues.
 
We documented the whole startup process in `docs/startup.md`.

Reseting the test server, just delete data folder. 
 
## Next Steps
- discuss server configurations
- Test the limitations further (rate limits, upload size)
- Figure out a way to deploy a web-client without DNS/domain, or get access to a domain. Maybe ask Martin?
- Write a small script or doc for self-service user setup, so people don't need shell access to the server. Or think of a good way to create an account?
- somehow the server needs to get managed? 
- add someway to analyze uptime and auto restart if problem?
- backups?


## 29.07.2026 - cj

We moved the test setup from SQLite to Postgres, since Synapse's docs say SQLite is only good for a few users, and we're trying to get 500 users working.

`docker-compose.yaml` runs `postgres:16-alpine` alongside Synapse, with a healthcheck.

Every important secret is in the `.env`.

Also changed how `homeserver.yaml` gets created — there is now a template that gets rendered. Do not change `homeserver.yaml` directly, only edit the template.

Setup uses the Synapse `generate` script once at the beginning to bootstrap, so we get the signing key, then we overwrite the generated `homeserver.yaml`, creating a new one from the template plus the `.env` values. Going forward, config changes happen in the template, not by hand-editing the generated file — just run setup again to apply changes. Should load everything correctly and start the server again (not tested).

Also pinned the Synapse version to `1.157.0`, so upgrades are now manual instead of stuff randomly breaking.

To reset the test server: stop it, delete the `/data/` folder, and change the secrets in `.env`. I used random 32-byte hex strings via `openssl rand -hex 32`. This does not really matter since it is a test server but in the actuall one this one needs to be difficult to guess.

## Next Steps
- `oidc_providers`: Switch-edu-id via MAS
- rate limiting overrides (defaults atm)
- TLS is terminated by Nginx, not Synapse, once reverse proxy is added
- Nginx + Element Web?
- everything from 27.07.2026 as well

## 08.08.2026 - cj

We set up the admin UI and used https://github.com/etkecc/ketesa.
It runs in its own container behind a Nginx vhost (if we have a domain we could/should change maybe?) bound to localhost.
Reachable only using `ssh -L 8443:localhost:8443 <vm-host>` -> `https://localhost:8443`
Read docs/admin-ui.md for more.
Did not work with firefox.


## 21.08.2026 - nkl, vs 

We read through the last steps and checked out the changes made.
Figured out a way to get the admin console to work -> Safari and Firefox do not work, while Chrome and Brave (Chromium based) do.
-> we do not know the exact reason, but since this is not prod we accept it for now

To solve the issue of creating accounts without Oidc/ldap: There is the possibility to use Registration tokens, but initially this did not work as the server is not configured for this
-> Editing template, appending:
```
enable_registration: true
registration:requires_token: true
```
and restarting the docker compose worked.

This allows a user with a respective token to create their account on their own and could serve as an alternative (creating such a token for each person who should have access)

We played around with trying to get Bots working for a while, but no luck so far. I set up maubot in the corresponding subdirectory, but it did not work, I think we just have to change the config though.


## Next steps
-> Next important step is definitely to get ITS involved, since we need the final prod VM & domain to really start setting everything up and converting this into a usable project (nginx with reverse proxy, tls, element web)
- Also: oidc / ldap through switch 
- Possible improvements until then: 
    - Create a proper deployment system (e.g. ansible)
    - Configure the admin panel properly 
    - Include and test bots 
    - Include and test VoIP (calls) -> this probably needs to be outside VPN too

## 30.08.2026 - nkl

Tried fixing the maubot instance. For better overview moved existing work to a separate `bot` branch and created a new `bot-working` branch, because it seemed easier to start anew. 
Encountered multiple problems, but managed to get it working in the end. Added documentation in /documents/maubot.md. 
Bots can now be used and (more or less) easily added. Maybe I can showcase it in the meeting on Monday.

New future problem: How will we expose this to professors etc. who want to add and manage their own bots?
-> we cannot really hand out admin credentials to maubot and have everyone working in the same space. I believe we need to code a self-service portal which talks to maubots REST API ?
-> Only other option is that we take care of this ourselves and Profs etc. can give us requests to integrate new bots -> does not seem like a good idea to me

## 01.09.2026 - cj

Wrote backup.sh for backups. pg_dump followed by rsync of media_storage, signing key, and homeserver.yaml, packed into a single .tar and moved into place atomically. Can be run if the server is running, could maybe lead to problem if really unucky like big files get uploaded after pg_dump and before rsync of media_storage (maybe). Rotation keeps N backups right now 1 day, can be changed.

## Next steps
    - we should think about moving the backup away from the server...
    - test restore

## 04.09.2026 - cj

Wrote a restore.sh to restore backups. it takes the backup tar and completely overwrites the current stages with the backup. 
Use the script like this: bash restore.sh "path to backup tar file"
!! Important !! The server gets restarted in the script and all media and files that were send after the backup are lost.

## Next step 
    - change all to ansible if possible maybe?

## 22.09.2026 - vs, cj

First login on the ITS VM (`dmi-matrix.dmi.unibas.ch`, service name `matrix.dmi.unibas.ch`), managed by ITS through ALIS (Ansible). Only looked around, nothing changed or installed yet.
In the repo: added a `.gitignore` for everything that must stay on the server (secrets, rendered configs, data, certs, backups), a proposed deployment plan in `docs/deployment.md` and PR #1 with the repo preparation (step 1 of the plan). Summary, doc and PR were prepared with Claude Code as proposals, the team decides.

What we found on the server:
- **System:** Ubuntu 26.04, 4 vCPU, 7.2 GB RAM, 1 TB disk (as allocated). Login with the unibas short login, sudo works.
- **ALIS roles:** `wsym.common`, `wsym.postgres`, `wsym.docker`, `wsym.letsencrypt`, runs regularly in "Live" mode. Files managed by ALIS should not be edited by hand, they may get overwritten. The ALIS playbook view contains access tokens: never copy them anywhere.
- **Storage:** Volume group `sysvg` has ~973 GB free, but the mounted volumes are small: `/` 6 GB (81 % used), `/opt` 4 GB, `/var` 6 GB, `/var/lib/postgresql/backups` 8 GB. Docker uses the default `/var/lib/docker` (no `daemon.json`) -> `/var` is too small for Docker + media, needs more space before deploying.
- **Docker:** Docker 29.1, Compose 2.40 installed. We are not in the `docker` group yet, `sudo docker` works. Pulling from Docker Hub works.
- **Nginx:** running, but only a `redirect` site on port 80. Nothing listens on 443 yet, no vhost for us.
- **TLS:** Let's Encrypt cert in `/etc/ssl/` covers only `dmi-matrix.dmi.unibas.ch`, not `matrix.dmi.unibas.ch`.
- **DNS:** `matrix.dmi.unibas.ch` already points to the VM.
- **Postgres:** Postgres 18 on the host, listens on 5432 (allowed from uni networks only, not from the Docker network). Local backups in `/var/lib/postgresql/backups`, not copied off the VM according to the ALIS config.
- **Network:** GitHub, ghcr.io (Synapse image) and dock.mau.dev (Maubot image) are reachable.
- **SSH:** tunnels to localhost are allowed, so the admin UI via `ssh -L` will work.
- "System restart required" is shown at login.

Storage: created a 500 GB LV `sysvg/marvinlv` (ext4), mounted on `/MARVIN` via `/etc/fstab` (by UUID), ~470 GB free in the VG left unallocated. Created group `marvin` for shared access to `/MARVIN`.

## Next steps
- Decide: Postgres in Docker or the ITS Postgres 18
- Clarify with ITS: nginx vhost on 443, docker group, reboot, Postgres backups off the VM
- Then: clone into `/MARVIN`, `.env`, `setup.sh`, first test deploy

## 29.09.2026 - cj

First deployment test of the stack on the ITS VM (`dmi-matrix.dmi.unibas.ch`).

### What we tried:
1. **Server Name Choice**: Decided on `matrix.dmi.unibas.ch` (service name) rather than `dmi-matrix.dmi.unibas.ch` (canonical host name) for the Matrix homeserver name, as Matrix User IDs (`@user:matrix.dmi.unibas.ch`) and the signing key are permanently bound to it.
2. **Disk Storage**: The root/var partitions were small; extended `/var` by +40 GB (`sysvg-varlv` to 46 GB) to ensure Docker image layers and container volumes do not exhaust disk space.
3. **Docker Stack Setup**:
   - Initial run of `setup.sh` failed due to missing Docker socket permissions (`permission denied while trying to connect to the docker API at unix:///var/run/docker.sock`). Resolved by adding the user to the `docker` group (`sudo usermod -aG docker $USER`).
   - Re-running `./setup.sh` generated the signing key, rendered configuration files, and started the stack (Postgres, Synapse, Ketesa admin UI, Maubot, admin Nginx) successfully.
4. **Host Nginx & Reverse Proxy**:
   - External HTTPS requests failed initially because nothing was listening on port 443 (`curl: (7) Failed to connect to matrix.dmi.unibas.ch:443`).
   - Configured a host Nginx reverse proxy site for `matrix.dmi.unibas.ch` forwarding `/_matrix`, `/_synapse/client`, and `/.well-known/matrix` to `127.0.0.1:8008` (using updated `http2 on;` directive and proxy timeouts for long-polling).
   - Pointed TLS config temporarily to the host's existing certificate `/etc/ssl/dmi-matrix.dmi.unibas.ch.cert.pem`. `nginx -t` passed and Nginx reloaded cleanly.
5. **Client Connection & Login**:
   - Created an admin user via `register_new_matrix_user`.
   - Attempted login via Element Desktop to `https://matrix.dmi.unibas.ch`.

### What failed and why:
- **Element stuck syncing (`ERR_CERT_COMMON_NAME_INVALID`)**:
  While the initial connection was accepted, Element remained perpetually stuck syncing. Inspecting the Electron/Chromium Developer Tools revealed `ERR_CERT_COMMON_NAME_INVALID`.
  - **Why:** The Let's Encrypt certificate on the VM was issued solely for `dmi-matrix.dmi.unibas.ch` and lacks `matrix.dmi.unibas.ch` in its Subject Alternative Names (SAN). Element's background sync workers strictly enforce SSL certificate hostname verification and blocked all `/sync` requests.
- All temporary configuration changes on the VM were reverted back to a clean state.

### Next steps:
- Try again, with other cert, or change nginx conf, because the problem is most likely there

## 02.10.2026 - vs, cj

Fixed the failed deployment from 29.09. The server now runs on the VM and is reachable at `https://matrix.dmi.unibas.ch`. We tested sending messages and group chats with Element Desktop, both work.

### What was wrong:
- **Wrong certificate:** ITS had already issued a Let's Encrypt cert for `matrix.dmi.unibas.ch` via ALIS (`wsym_letsencrypt`, DNS-01) on 29.09, in `/etc/ssl/matrix.dmi.unibas.ch.{fullchain,privkey}.pem`. But the host nginx vhost still pointed to the `dmi-matrix.dmi.unibas.ch` host cert -> `ERR_CERT_COMMON_NAME_INVALID` in Element. Also, the vhost in `/etc/nginx/sites-available/` was a separate copy, so editing the repo file changed nothing.
- **Old Postgres volume:** the containers and the `postgres_data` volume from the 29.09 test were still there. Postgres keeps the password from its first start, so with the new `.env` secrets Synapse and Maubot failed with `password authentication failed for user "synapse"` and kept restarting (admin nginx followed, because it could not find `maubot`). `setup.sh` just waited forever without any output.

### What we did:
- `server/nginx/matrix.conf` now uses the `matrix.dmi.unibas.ch` fullchain + privkey. Removed our port-80 block, the ALIS `redirect` site already does HTTP -> HTTPS (and renewal uses DNS-01, so port 80 is not needed for it).
- `/etc/nginx/sites-available/matrix.dmi.unibas.ch.conf` is now a symlink to `/MARVIN/matrix-unibas/server/nginx/matrix.conf` (old copy backed up in the home folder). Config changes: `git pull`, then `sudo nginx -t && sudo systemctl reload nginx`.
- Tested from outside: correct cert (valid until 28.12.2026, chain ok), HTTP -> HTTPS redirect, `/` and `/_synapse/admin` give 404, `/_matrix` reaches Synapse.
- `docker compose down -v` to remove the old test volume, then `./setup.sh` again -> all containers up.
- Created an admin user with `register_new_matrix_user`, logged in with Element Desktop, tested messages and groups.

To fully reset the server: `docker compose down -v` (deletes the Postgres volume!), not only deleting `data/`.

### Admin UI:
Logging in to the admin UI (Ketesa) through the SSH tunnel worked, but fetching data did not. We switched to running Ketesa locally on the laptop (`docker run --rm -p 8080:8080 ghcr.io/etkecc/ketesa:latest` -> `http://localhost:8080`, homeserver `https://matrix.dmi.unibas.ch`). For this, the host nginx now forwards `/_synapse/admin` to Synapse, but only from the uni network (`131.152.0.0/16`) and internal/VPN addresses (`10.0.0.0/8`), everyone else gets 403. Works now, see `server/docs/admin_ui.md`. The admin UI containers in the stack (`synapse-admin`, `nginx-admin`) are no longer needed.

### VoIP / Coturn (STUN/TURN):
Integrated Coturn into the stack to support 1:1 voice and video calls in Element/Matrix clients when users are behind NAT or firewalls.

- **Docker Compose**: Added the `coturn` service (`coturn/coturn:latest`) with `network_mode: host` to allow direct access to network interfaces without Docker port forwarding overhead for WebRTC UDP media traffic.
- **Coturn configuration**:
  - Added template [server/coturn/turnserver.conf.template](file:///home/chris/Documents/unibas/Matrix_uni/matrix-unibas/server/coturn/turnserver.conf.template).
  - Configured STUN/TURN listening ports on 3478 and TLS on 5349.
  - Configured shared secret authentication (`use-auth-secret`, `static-auth-secret`) for Matrix.
  - Defined relay UDP port range `49152-49200`.
  - Added SSRF protection (`denied-peer-ip`) against private IP ranges (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `127.0.0.0/8`).
- **Secrets & setup scripts**:
  - Added `SYNAPSE_TURN_SHARED_SECRET` to `.env.example`.
  - Updated `create_env.sh` to generate a random 32-byte hex TURN secret automatically.
  - Updated `setup.sh` to validate `SYNAPSE_TURN_SHARED_SECRET`, create `server/coturn/`, and render `server/coturn/turnserver.conf` via `envsubst`.
  - Added `**/coturn/turnserver.conf` to `.gitignore` so rendered credentials are not tracked.
- **Synapse configuration**:
  - Updated `server/homeserver.yaml.template` with `turn_uris` (UDP and TCP on port 3478), `turn_shared_secret`, `turn_user_lifetime: 2h`, and `turn_allow_guests: false`.
