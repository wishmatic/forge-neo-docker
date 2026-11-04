# Forge Neo (Docker)

Forge Neo ([`sd-webui-forge-classic`, `neo` branch][forge]) in an image built against CUDA 13, with
the base image, the Forge commit and every wheel pinned. Needs a driver that supports CUDA 13;
`sm_120` (RTX 50xx) included.

[forge]: https://github.com/Haoming02/sd-webui-forge-classic/tree/neo

## Deploy

```sh
docker run --detach \
    --name sdwui-forge-neo \
    --init \
    --gpus all \
    --restart unless-stopped \
    --user 99:100 \
    --publish 7860:7860 \
    --volume /mnt/user/appdata/sd-webui/models:/home/forge/sd-webui/models \
    --volume /mnt/user/appdata/sd-webui/extensions:/home/forge/sd-webui/extensions \
    --volume /mnt/user/appdata/sd-webui/config:/home/forge/sd-webui/config \
    --volume /mnt/user/appdata/sd-webui/cache:/home/forge/sd-webui/cache \
    --volume /mnt/user/data/sd-webui/output:/home/forge/sd-webui/output \
    ghcr.io/wishmatic/sd-webui-docker:latest
```

Create those directories owned by 99:100 first.

Never mount `/home/forge/sd-webui` as a whole: it hides the venv baked into the image. `config`
holds `config.json`, `ui-config.json`, `styles.csv` and `params.txt`; without it every recreate
resets the UI and saved prompts.

## Arguments

`COMMANDLINE_ARGS` defaults to:

```sh
--api --listen --skip-install --skip-python-version-check --enable-insecure-extension-access
```
