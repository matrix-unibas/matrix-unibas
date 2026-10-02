## Connecting to the admin UI

The admin UI ([Ketesa](https://github.com/etkecc/ketesa)) runs locally on your own machine. It is only a browser app, all data comes from the Synapse admin API at `https://matrix.dmi.unibas.ch/_synapse/admin`, which the host nginx only allows from the uni network / VPN (see `nginx/matrix.conf`).

**1. Create an account and make it a server admin** (on the VM)
```bash
docker exec -it matrix-synapse register_new_matrix_user \
  -c /data/homeserver.yaml -a http://localhost:8008
```
Note: `-a` flag creates the user directly as server admin. Server admin ≠ room admin: this flag makes the account able to use the `/_synapse/admin` API.
Use a strong password, the admin API is reachable from the whole uni network.

**2. Start Ketesa locally** (on your laptop, connected to the uni network or VPN)
```bash
docker run --rm -p 8080:8080 ghcr.io/etkecc/ketesa:latest
```

**3. Connect with a browser**
- Go to `http://localhost:8080`
- Homeserver URL: `https://matrix.dmi.unibas.ch`
- Log in with the admin username/password from step 1.

Outside the uni network / VPN, the admin API answers with `403 Forbidden`.

Done.
