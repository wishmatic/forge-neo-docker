# Forge Neo (Docker)

Forge Neo ([`sd-webui-forge-classic`, `neo` branch][forge]) in an image built against CUDA 13, with
the base image, the Forge commit and every wheel pinned. Needs a driver that supports CUDA 13;
`sm_120` (RTX 50xx) included.

[forge]: https://github.com/Haoming02/sd-webui-forge-classic/tree/neo

## Run

```sh
./build.sh
./run.sh --recreate
./verify.sh --recreate
```

`run.sh` reads `IMAGE`, `CONTAINER`, `PORT` and `APPDATA` from the environment. The container runs
as 99:100, gets `--gpus all`, and serves on port 7860.

## Arguments

`COMMANDLINE_ARGS` defaults to:

```sh
--api --listen --skip-install --skip-python-version-check --enable-insecure-extension-access
```

Override per container with `-e COMMANDLINE_ARGS=...`. Keep `--skip-install` as that prevents `pip`
runs at boot.

## Updating

```sh
./scripts/check-forge-update.sh
./scripts/compile-deps.sh
./build.sh
./verify.sh --recreate
```

Roll back with `IMAGE=forge-neo:digest-<id> ./run.sh --recreate`. CI pushes `:latest` and
`:forge-<sha>` to `ghcr.io/<owner>/<repo>` on `main`.
