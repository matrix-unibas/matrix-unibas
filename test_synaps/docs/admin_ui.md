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
  -c /data/homeserver.yaml http://localhost:8008
```
```bash
docker exec -it matrix-postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -c "UPDATE users SET admin = 1 WHERE name = '@USERNAME:${SERVER_NAME}';"
```
Note: server admin ≠ room admin. This flag makes the account able to use the `/_synapse/admin` API, regardless of what rooms it's in.

**4. Connect with a browser**
NOTE: Safari on macOS and Firefox on Linux do not work! -> workaround is to use Brave or Chrome

- Go to:
```
https://localhost:8443
```
- Browser will warn about the certificate, it's self-signed on purpose, the admin UI is not meant to be publicly.
- Use `http://10.34.64.160:8008` as server URL
- Log in with the username/password from step 3

Done.
