# Forge Neo (Docker)

An image for [sd-webui-forge-classic, `neo` branch][forge], built from scratch, with every
input pinned: base image by digest, Forge by commit, and every wheel by hash in
`requirements.lock`.

The target is an RTX 5070 Ti / 5080 (compute capability 12.0, `sm_120`) on Unraid, with a
host driver that supports CUDA 13. Any `sm_120` card will do; nothing here is deliberately
single-host.

[forge]: https://github.com/Haoming02/sd-webui-forge-classic/tree/neo

## Why this exists

The image this replaces is abandoned (last commit April 2026) and was built for CUDA 12.4.
The container that ended up running used Python 3.13 and torch `2.14.1+cu126`. Torch `cu126`
has no `sm_120` kernels, so every CUDA op failed, and Forge reported the failure as
`Encountered Out of Memory during Sampling`. It was never a memory problem — do not go
looking for one.

The second half of the problem is structural: the venv lived inside the container's writable
layer. It survived `docker restart` and disappeared on `docker create`, which is how the
runtime drifted to a torch that could not run.

So: the venv is baked into the image, pip is constrained to the lock on every invocation,
and Forge runs with `--skip-install` so nothing can be installed at boot.

## What is pinned

| Input               | Pin                                            | Where               |
| ------------------- | ---------------------------------------------- | ------------------- |
| Base image          | `nvidia/cuda:13.0.2-cudnn-runtime-ubuntu24.04` | `Dockerfile`        |
| Forge               | `286a244ec2056882471b09a3a4ea6c2cd1c450f6`     | `ARG FORGE_REF`     |
| Python              | 3.12.3, from Ubuntu 24.04                      | base image          |
| torch / torchvision | `2.14.1+cu130` / `0.29.1+cu130`                | `requirements.lock` |
| xformers            | `0.0.35`, pinned to the `cu130` wheel URL      | `requirements.in`   |
| Every other package | `uv pip compile --generate-hashes`             | `requirements.lock` |
| Installer           | uv 0.13.7, digest-pinned                       | `Dockerfile`        |
| apt packages        | the set, not the patch versions                | `Dockerfile`        |

The lock is compiled from `requirements.in`, Forge's own `requirements.txt` and `extras.txt`
by a verified build's toolchain. It is installed with `--require-hashes`, so every wheel is
pinned by digest and not just by version. The image also derives `/etc/pip-constraints.txt`
from the lock at build time and exports it as `PIP_CONSTRAINT`, so the pip call `webui.sh`
makes on every start cannot move anything. `verify.sh` compares the installed set to it.

## Build, run, verify

```sh
./build.sh                 # tags forge-neo:forge-<sha>, :digest-<id>, :latest
./run.sh --recreate        # (re)create the container
./verify.sh                # arch list, matmul, xformers, 512x512 render, pin diff
./verify.sh --recreate     # same, after a recreate, asserting the image id is stable
```

`run.sh` reads `IMAGE`, `CONTAINER`, `PORT` and `APPDATA` from the environment; `APPDATA`
defaults to `/mnt/user/appdata/forge-neo`.

## Mounts

Never mount `/home/forge/sd-webui` as a whole: that hides the baked venv, which is exactly
the failure this repo exists to prevent.

| Host (`$APPDATA/…`) | Container                                |
| ------------------- | ---------------------------------------- |
| `models`            | `/home/forge/sd-webui/models`            |
| `embeddings`        | `/home/forge/sd-webui/models/embeddings` |
| `output`            | `/home/forge/sd-webui/output`            |
| `extensions`        | `/home/forge/sd-webui/extensions`        |
| `config`            | `/home/forge/sd-webui/config`            |
| `cache`             | `/home/forge/sd-webui/cache`             |

`config` holds `config.json`, `ui-config.json`, `styles.csv`, `styles_integrated.csv` and
`params.txt`. Forge writes those into the webui directory, so the image keeps symlinks in
`/home/forge/sd-webui` pointing at `config/`. Without that mount every recreate silently
resets the UI and saved prompts.

Embeddings live at `models/embeddings` because that is Forge's default (`--embeddings-dir`);
the host directory name is unchanged.

The container runs as UID 99 / GID 100 with `--gpus all`, on port 7860.

## Verification

`verify.sh` checks, in order:

1. `torch.cuda.get_arch_list()` contains `sm_120`, and torch was built for CUDA 13.x.
2. Every installed distribution matches the pin derived from `requirements.lock`, and nothing
   is installed that is not pinned (`ALLOWED_TO_FLOAT` in the script is the escape hatch).
3. A 64×64 matmul on `cuda` returns a number.
4. `xformers` imports, has its C++ library, came from the `cu130` index, and
   `memory_efficient_attention` runs on the GPU.
5. A 512×512, batch 1, no-hires render through `/sdapi/v1/txt2img` returns one image of the
   right size.

With `--recreate` it re-creates the container first and asserts `docker inspect` reports the
same image id, then renders again.

`--image IMAGE` runs the checks that need neither a GPU nor a server. A build that passes
steps 1–2 and fails the render is still broken.

Set `VERIFY_CHECKPOINT` to pick a specific checkpoint and `VERIFY_STEPS` to change the step
count.

## Migrating off the broken container

Do this on the host before deploying anything:

```sh
docker commit sdwui-forge-neo sdwui-forge-neo:cu130-working
```

That is both a rollback point and a `pip freeze` source. It is not a fix — the writable layer
it saves disappears with the next recreate.

The old container kept `config.json`, `ui-config.json`, `styles.csv` and `params.txt` in its
writable layer. Copy them out if you want to keep the UI layout:

```sh
for f in config.json ui-config.json styles.csv styles_integrated.csv params.txt; do
    docker cp "sdwui-forge-neo:/home/forge/sd-webui/$f" "$APPDATA/config/" 2>/dev/null || true
done
```

Then `./run.sh --recreate` mounts that directory over the symlinks and the settings survive
from then on.

## Update policy

**Forge.** `scripts/check-forge-update.sh` compares the pinned commit with upstream `neo`,
prints the commits in between, and exits non-zero when there are some. Bumping `FORGE_REF` is
a human decision, followed by `./build.sh` and `./verify.sh`.

**Base image and torch.** Renovate tracks the base image tag and digest (Tuesdays, no
automerge). The venv moves only by recompiling the lock:

```sh
./scripts/compile-deps.sh   # rewrites requirements.lock
./build.sh
./verify.sh
```

`compile-deps.sh` resolves for the image's platform, not yours, and pulls Forge's own
`requirements.txt` from the pinned commit, so bump `FORGE_REF` before running it.

**Rollback.** Images are tagged `forge-<commit>` and `digest-<image id>`, so rolling back is
`IMAGE=forge-neo:digest-<id> ./run.sh --recreate`. `IMAGE` also works with `verify.sh`.

**Registry copy.** CI builds and pushes to `ghcr.io/<owner>/<repo>` on `master`, as `:latest`
and `:forge-<sha>`. Nothing is pushed to Docker Hub.

## Things that look wrong but are not

- **Python 3.12, while Forge prints "tested with 3.13.15".** 3.12 is the version upstream's
  previous image settled on for wheel coverage. `cp313` wheels for torch and xformers do
  exist on the `cu130` index now, so flipping is a one-line change plus a verify — but it is
  not free, and nothing here needs it. `--skip-python-version-check` only silences the banner.
- **`--xformers` is absent from `COMMANDLINE_ARGS`.** In `neo` that flag means _install_
  xformers, not _use_ it. Attention selection is automatic (`backend/memory_management.py`),
  so a baked-in xformers is picked up on its own. `--disable-xformers` or
  `--use-pytorch-cross-attention` would turn it off.
- **`--skip-torch-cuda-test` is absent.** Deliberately. It is the check that turns an
  arch/ABI mismatch into a startup failure instead of an "OOM" halfway through a render.
- **`--skip-install` is set.** It stops boot-time pip and extension installers. Anything an
  extension needs belongs in `extras.txt`, compiled into the lock at build time.
- **gradio is installed with `--no-deps`.** gradio 4.40.0 (the version Forge pins) declares
  `pillow<11`, and Forge pins `Pillow==13.0.0`. With dependencies the resolver either fails
  against the lock or quietly downgrades Pillow; gradio is the one package outside the lock,
  and its closure is pinned inside it.
- **xformers is pinned by URL, not version.** PyPI publishes `0.0.35` too, built against
  another CUDA, and the version strings are identical. The URL in `requirements.in` is the
  only unambiguous pin; `verify.sh` checks the wheel's recorded source.
- **`uv` is in the image.** It is the installer, and Forge can use it too (`--uv`).
- **No torchaudio.** The `cu130` index tops out at torchaudio 2.11 while torch is 2.14; it
  would drag a second torch in. Forge does not use it.
- **xformers failures are silent.** `backend/attention.py` catches the exception and falls
  back to pytorch attention with a warning in the log. Generation still works, slower, which
  is why `verify.sh` runs the op itself.

## Troubleshooting

`Out of Memory during Sampling` is a generic message from a handler that catches CUDA errors.
Before touching VRAM, run:

```sh
docker exec sdwui-forge-neo python -c \
    "import torch; print(torch.version, torch.version.cuda, torch.cuda.get_arch_list())"
docker exec sdwui-forge-neo python -c \
    "import torch; a = torch.randn(64, 64, device='cuda'); print((a @ a).sum().item())"
```

If the second command raises `no kernel image is available for execution on the device`, the
torch build has no kernels for this GPU; `+cu126` in the version string says nothing either
way.

If the pins have moved, something installed a package outside the lock. `./verify.sh --static`
prints what differs.
