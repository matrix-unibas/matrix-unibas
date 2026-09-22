# Maubot

## Preparation
-> similar to Admin console

**1. Start the server** (if not already running)
```bash
./setup.sh
```

**2. Open an SSH tunnel to the VM for the Maubot admin UI**
```bash
ssh -L 29316:localhost:29316 ubuntu@10.34.64.160
```
Leave this running — it's the only path in. The admin UI is bound to `127.0.0.1` on the VM, not the VPN-facing interface, so there is no direct network route to it.

**3. Create an account** 

An `admin` account for the maubot UI is created automatically and the password is set in the `.env` file.

**4. Connect with a browser**
NOTE: (Probably) Safari on macOS and Firefox on Linux do not work! -> workaround is to use Brave or Chrome

- Go to:
```
https://localhost:8443/_matrix/maubot/
```
- Browser will warn about the certificate, it's self-signed on purpose, the admin UI is not meant to be publicly.
- Log in with the username/password from step 3

## Creating a bot

First of all choose your plugin. There sadly currently is no official repository or central location, but there is a list here: [https://plugins.mau.bot/](https://plugins.mau.bot/). You need to either download a realease (.mbp file) or build the plugin yourself.
Once you have the .mbp file:

Click `+` next to the Plugins header and drop the .mbp file there.

Next up you need to either create a new client or you may choose to omit this step and use an existing one (that will then perform the tasks your plugin implements in addition to what it already does).
Clients are basically normal matrix users and need to be created as such. To avoid having to do all of it manually (which also causes issues with the verification) use these commands:

### Creating the account

You can do this through the ketesa admin UI or the documented commands. Create a new account, with the username and password you would like to set for the bot.

### Logging in

```bash
docker exec -it matrix-maubot /usr/bin/python3 -m maubot.cli login
```

Use the admin username and password from Preparations and `http://locahost:29316` for the Server. You may omit Alias.

### Creating the bot account

Once logged in as a maubot admin, you need to request an access token for the bot / create the bot account:

```bash
docker exec -it matrix-maubot /usr/bin/python3 -m maubot.cli auth --update-client
```

Fill in the homeserver as defined in homeserver.yaml.template (here: `dmi.matrix.unibas.ch`), fill in the username and password for the bot. The --update-client flag should automatically create the client for you in the maubot web-ui. If that is not the case follow the creating the client step, if everything worked, continue with the verification (optional, but recommended)


### Creating the client -- OPTIONAL IN CASE OF ISSUES

Take note of the access token and device ID returned to you by the last command, we need them now.

Open the maubot admin UI again and click the `+` next to the client header. Fill in the username (e.g. @bot:dmi.matrix.unibas.ch), access token and device ID from before. Click on save and the client should start.

The bot is now created and can already be used. 


### Verify the bot account

In the maubot web-ui click on the newly created client, click on generate recovery key, copy the key, click on verify and paste it in the browser pop-up. After a few seconds the bot should now be verified.

### Verifying the bot manually -- OPTIONAL IN CASE OF ISSUES

There are 2 options:

1. Log into element with the bot account using the username password you gave it, generate a Recovery Key in Settings/Encryption, go to the admin UI, click on your client, click on verify, paste the recovery key, click okay -> client should now be verified.
2. (untested)
    - Stop the docker container (docker stop matrix-maubot)
    - Start the interactive postgres session:
    ```bash 
    docker exec -it matrix-postgres psql -U synapse -d maubot
    ```
    - Update the device ID manually
    ```psql
    UPDATE client SET device_id='<DEVICE_ID>' WHERE id='<MXID>';
    UPDATE client SET device_id='<DEVICE_ID>', access_token='<ACCESS_TOKEN>' WHERE id='<MXID>';
    \q
    ```
    - Restart the container: ```docker start matrix-maubot```

### Creating the instance

This is the last step, basically connecting your client to the features from your plugin.
Click on the `+` next to the Instances header and give the instance a sensible name. Leave enabled and running on on (unless you specifically want to have to manually start the bot later), choose your client as the primary user and your plugin for the type. CLick on create. The bot should now function and you can test it in your matrix client of choice:

Invite the bot to a chat/room and use commands it supports (e.g. !echo or !roll).