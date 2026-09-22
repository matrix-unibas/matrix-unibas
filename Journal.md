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
