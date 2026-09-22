## Connecting to the test Synapse server

**1. Start the server**
```bash
./setup.sh
```

**2. Create an account** (skip if you already have one)
```bash
docker exec -it synapse-test register_new_matrix_user \
  -c /data/homeserver.yaml http://localhost:8008
```

**3. Connect with a client** (only tested with Element)
- Open Element → **"Sign in"** → **"Edit"** next to the homeserver field
- Enter the custom homeserver:
`http://<server-ip>:<port>`
```
Currently: `http://10.34.64.160:8008`
```
- Log in with the username/password from step 2

Done.