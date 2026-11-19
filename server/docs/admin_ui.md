## Connecting to the admin UI

The admin UI ([Ketesa](https://github.com/etkecc/ketesa)) runs locally on your own machine. It is only a browser app; all data comes from the Synapse admin API. That API is **not reachable from the internet or the uni network**: the host nginx answers `/_synapse/admin` with `403` for everyone (`nginx/matrix.conf`). You reach it only through an SSH tunnel to the admin nginx container (`nginx/admin.conf`, `127.0.0.1:${ADMIN_UI_PORT}` = 8443 on the VM), the same tunnel as for the maubot UI ([maubot.md](maubot.md)).

**1. Create an account and make it a server admin** (on the VM, once)
```bash
docker exec -it matrix-synapse register_new_matrix_user \
  -c /data/homeserver.yaml -a http://localhost:8008
```
Note: `-a` flag creates the user directly as server admin. Server admin ≠ room admin: this flag makes the account able to use the `/_synapse/admin` API. Use a strong password anyway: the normal login is public.

**2. Open the SSH tunnel** (on your laptop)
```bash
ssh -L 8443:localhost:8443 <unibas-user>@dmi-matrix.dmi.unibas.ch
```

**3. Accept the tunnel's certificate once.** The admin nginx uses a self-signed certificate. Open `https://localhost:8443/_matrix/client/versions` in the browser you will use for Ketesa and accept the warning; otherwise Ketesa's requests fail with a network error.

**4. Start Ketesa locally** (on your laptop)
```bash
docker run --rm -p 8080:8080 ghcr.io/etkecc/ketesa:latest
```

**5. Connect with a browser**
- Go to `http://localhost:8080`
- Homeserver URL: `https://localhost:8443`
- Log in with the admin username/password from step 1.

Without the tunnel, Ketesa can't reach the admin API at all.

Done.

### Why not through the public domain

Until 2026-11-20 the host nginx passed `/_synapse/admin` through for the uni network and VPN (`131.152.0.0/16`, `10.0.0.0/8`), i.e. for every student on campus or on the VPN. The API still needed an admin token, but a stolen admin token (or a bug in an admin endpoint) was then usable from the whole university. Nothing needs the public route: the admin bot talks to `http://synapse:8008` on the Docker network, `register_new_matrix_user` runs inside the container, and Ketesa works through the tunnel.
