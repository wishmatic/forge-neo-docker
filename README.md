# Forge Neo (Docker)

This image runs Forge Neo ([`sd-webui-forge-classic`, `neo` branch][forge]) on CUDA 13. The
Dockerfile pins the base image, the Forge commit and every wheel. You need a driver that supports
CUDA 13, and any `sm_120` card (RTX 50xx) works.

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
    ghcr.io/wishmatic/forge-neo-docker:latest
```

Create the directories first and give them to 99:100.

Never mount `/home/forge/sd-webui` as a whole, because that hides the venv the image bakes in.
The `config` mount holds `config.json`, `ui-config.json`, `styles.csv` and `params.txt`. Without
it, every recreate resets the UI and saved prompts.

## Arguments

The image sets `COMMANDLINE_ARGS` to:

```sh
--api --listen --skip-install --skip-python-version-check --enable-insecure-extension-access
```

## Pinning

| File                      | Why it exists                                               |
| ------------------------- | ----------------------------------------------------------- |
| `requirements.lock`       | What the image installs.                                    |
| `requirements.in`         | Versions to edit.                                           |
| `extras.txt`              | Packages mounted extensions need.                           |
| `scripts/compile-deps.sh` | Rebuilds the lock from them, plus Forge's requirements.txt. |

[forge]: https://github.com/Haoming02/sd-webui-forge-classic/tree/neo
