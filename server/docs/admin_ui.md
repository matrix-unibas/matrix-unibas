## Connecting to the admin UI

**1. Start the server** (if not already running)
```bash
./setup.sh
```

**2. Open an SSH tunnel to the VM**
```bash
ssh -L 8443:localhost:8443 <you>@<vm-host>
```
Leave this running — it's the only path in. The admin UI is bound to `127.0.0.1` on the VM, not the VPN-facing interface, so there is no direct network route to it.

**3. Create an account and make it a server admin** 
```bash
docker exec -it matrix-synapse register_new_matrix_user \
  -c /data/homeserver.yaml -a http://localhost:8008
```
Note: `-a` flag creates the user directly as server admin. Server admin ≠ room admin: this flag makes the account able to use the `/_synapse/admin` API.

**4. Connect with a browser**
NOTE: Safari on macOS and Firefox on Linux may fail due to strict self-signed certificate handling -> workaround is to use Brave or Chrome.

- Go to:
```
https://localhost:8443
```
- Browser will warn about the self-signed certificate (expected, since it is internal-only). Accept the certificate.
- Use `https://localhost:8443` as the homeserver URL.
- Log in with the admin username/password from step 3.

Done.
