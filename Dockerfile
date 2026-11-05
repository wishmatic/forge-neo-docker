# syntax=docker/dockerfile:1

FROM nvidia/cuda:13.0.2-cudnn-runtime-ubuntu24.04@sha256:14d94b039cb94bbd5da559f303b46bc4b0d5d6c24ab1a9d7b186e566ed3400dc

ARG TORCH_INDEX=cu130

ARG FORGE_REPO=https://github.com/Haoming02/sd-webui-forge-classic
ARG FORGE_REF=286a244ec2056882471b09a3a4ea6c2cd1c450f6

ARG UID=99
ARG GID=100

ARG GRADIO_VERSION=4.40.0
ARG GRADIO_RANGESLIDER_VERSION=0.0.8

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_CONSTRAINT=/etc/pip-constraints.txt \
    HF_HOME=/home/forge/sd-webui/cache/huggingface

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    python3.12 \
    python3.12-venv \
    python3.12-dev \
    build-essential \
    ninja-build \
    git \
    curl \
    ca-certificates \
    libgl1 \
    libglib2.0-0 \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid "${GID}" forge 2>/dev/null || true \
    && useradd --uid "${UID}" --gid "${GID}" --create-home --home-dir /home/forge --shell /bin/bash forge

COPY requirements.lock /tmp/requirements.lock
COPY scripts/lock_to_constraints.py /tmp/lock_to_constraints.py

COPY --from=ghcr.io/astral-sh/uv:0.13.7@sha256:96f40d3904aad8d0bd010539001d36c8e2188b981e1334471a90c4a1d93bb490 /uv /usr/local/bin/uv

RUN python3.12 /tmp/lock_to_constraints.py /tmp/requirements.lock \
    "gradio==${GRADIO_VERSION}" "gradio_rangeslider==${GRADIO_RANGESLIDER_VERSION}" \
    > /etc/pip-constraints.txt

USER forge
WORKDIR /home/forge

RUN git clone --branch neo "${FORGE_REPO}" sd-webui \
    && git -C sd-webui checkout --detach "${FORGE_REF}" \
    && test "$(git -C sd-webui rev-parse HEAD)" = "$(git -C sd-webui rev-parse --verify "${FORGE_REF}^{commit}")"

WORKDIR /home/forge/sd-webui

RUN uv venv venv --python /usr/bin/python3.12

ENV VIRTUAL_ENV=/home/forge/sd-webui/venv \
    PATH=/home/forge/sd-webui/venv/bin:/home/forge/.local/bin:/usr/local/bin:/usr/bin:/bin \
    PYTHON=/home/forge/sd-webui/venv/bin/python

RUN --mount=type=cache,target=/home/forge/.cache/uv,uid=99,gid=100,sharing=locked \
    uv pip install --require-hashes -r /tmp/requirements.lock \
    --index-url https://pypi.org/simple \
    --extra-index-url "https://download.pytorch.org/whl/${TORCH_INDEX}" \
    --index-strategy unsafe-best-match

RUN --mount=type=cache,target=/home/forge/.cache/uv,uid=99,gid=100,sharing=locked \
    uv pip install --no-deps \
    "gradio==${GRADIO_VERSION}" "gradio_rangeslider==${GRADIO_RANGESLIDER_VERSION}"

RUN mkdir -p \
    models/Stable-diffusion \
    models/VAE \
    models/Lora \
    models/ControlNet \
    models/embeddings \
    output \
    extensions \
    tmp \
    cache/huggingface \
    config \
    && for f in config.json ui-config.json styles.csv styles_integrated.csv params.txt; do \
    ln -s "config/$f" "$f"; \
    done

ENV COMMANDLINE_ARGS="--api --listen --skip-install --skip-python-version-check --enable-insecure-extension-access"

EXPOSE 7860

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=5 \
    CMD curl -fsS http://127.0.0.1:7860/ -o /dev/null || exit 1

ENTRYPOINT ["/home/forge/sd-webui/webui.sh"]
