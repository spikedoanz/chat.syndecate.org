# Basic info

Hostname: https://chat.syndecate.org
Chat backend: https://zulip.com/

--------------------------------------------------------------------------------

# All services used 

| Type      | Service           | Account               | Price / mo
|-----------|-------------------|-----------------------|---------------------
| Hosting   | hetzner.com       | spikedoanz@gmail.com  | 5.50 usd
| SMTP      | mailgun.com       | spikedoanz@gmail.com  | 0.00 usd
| Domain    | namecheap.com     | spikedoanz@gmail.com  | 1.3  usd (16 / year)

--------------------------------------------------------------------------------

# Backing up

```bash
su zulip
/home/zulip/deployments/current/manage.py backup
```

and then copy the file somewhere safe.
