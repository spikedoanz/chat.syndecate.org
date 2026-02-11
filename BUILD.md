# Primary sources

https://zulip.readthedocs.io/en/stable/production/install.html


# Current hardware specs

- 2vCPUs
- 2GB ram
- 40GB local

--------------------------------------------------------------------------------

# Instructions

1. Add some swap to the node
> current node doesn't have enough ram to host

```sh
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

2. Follow rest of instructions in the [core docs](
https://zulip.readthedocs.io/en/stable/production/install.html)


