import base64
import io
import json
import os
import re
import sys
import time
import urllib.request

API = os.environ.get("VERIFY_API", "http://127.0.0.1:7860")


def check_static():
    import torch

    archs = torch.cuda.get_arch_list()
    print(f"     torch {torch.__version__}, built for cuda {torch.version.cuda}")
    print(f"     archs: {' '.join(archs)}")

    if not torch.version.cuda.startswith("13."):
        sys.exit(f"torch was built for CUDA {torch.version.cuda}, expected 13.x")
    if "sm_120" not in archs:
        sys.exit("sm_120 is missing from torch.cuda.get_arch_list()")


def check_pins():
    from importlib.metadata import distributions

    def normalise(name):
        return re.sub(r"[-_.]+", "-", name).lower()

    wanted = {}
    with open("/etc/pip-constraints.txt", encoding="utf-8") as constraints:
        for line in constraints:
            line = line.strip()
            if line and not line.startswith("#"):
                name, _, version = line.partition("==")
                wanted[normalise(name)] = version

    allowed = {normalise(n) for n in os.environ.get("VERIFY_ALLOW_FLOAT", "").split()}
    installed = {normalise(d.metadata["Name"]): d.version for d in distributions()}

    drift = []
    for name, version in sorted(wanted.items()):
        if name in allowed:
            continue
        if name not in installed:
            drift.append(f"not installed: {name}=={version}")
        elif installed[name] != version:
            drift.append(f"{name}: pinned {version}, installed {installed[name]}")
    for name in sorted(set(installed) - set(wanted) - allowed):
        drift.append(f"installed but not pinned: {name}=={installed[name]}")

    if drift:
        sys.exit("drift from the lock:\n  " + "\n  ".join(drift))

    print(f"     {len(wanted)} pins, all matched")


def check_gpu():
    import torch
    import xformers
    import xformers.ops

    a = torch.randn(64, 64, device="cuda")
    print(f"     (64x64 @ 64x64).sum() = {float((a @ a).sum()):.6f}")

    print(
        f"     xformers {xformers.__version__}, cpp library: {xformers._has_cpp_library}"
    )
    if not xformers._has_cpp_library:
        sys.exit(
            "xformers has no C++ library; Forge would silently fall back to pytorch attention"
        )

    from importlib.metadata import distribution

    source = distribution("xformers").read_text("direct_url.json")
    if source:
        url = json.loads(source)["url"]
        print(f"     xformers source: {url}")
        if "download.pytorch.org" not in url:
            sys.exit(f"xformers came from {url}, not the torch index")

    q = torch.randn(2, 64, 8, 16, device="cuda", dtype=torch.bfloat16)
    out = xformers.ops.memory_efficient_attention(q, q, q)

    print(f"     xformers memory_efficient_attention -> {tuple(out.shape)} {out.dtype}")


def check_render():
    from PIL import Image

    def get(path):
        with urllib.request.urlopen(API + path, timeout=60) as response:
            return json.load(response)

    models = get("/sdapi/v1/sd-models")
    if not models:
        sys.exit(
            "no checkpoints in models/Stable-diffusion, so there is nothing to render with"
        )

    title = os.environ.get("VERIFY_CHECKPOINT") or models[0]["title"]
    payload = {
        "prompt": "a red cube on a wooden table, studio light",
        "negative_prompt": "",
        "width": 512,
        "height": 512,
        "steps": int(os.environ.get("VERIFY_STEPS", "8")),
        "batch_size": 1,
        "n_iter": 1,
        "cfg_scale": 4,
        "seed": 1,
        "enable_hr": False,
        "override_settings": {"sd_model_checkpoint": title},
        "override_settings_restore_afterwards": False,
    }

    request = urllib.request.Request(
        API + "/sdapi/v1/txt2img",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )

    started = time.time()
    with urllib.request.urlopen(request, timeout=1800) as response:
        result = json.load(response)

    images = result.get("images") or []
    if not images:
        sys.exit(f"txt2img returned no images: {json.dumps(result)[:400]}")

    image = Image.open(io.BytesIO(base64.b64decode(images[0])))
    elapsed = time.time() - started
    print(
        f"     rendered {image.size[0]}x{image.size[1]} with {title!r} in {elapsed:.1f}s"
    )

    if image.size != (512, 512):
        sys.exit(f"expected a 512x512 image, got {image.size}")
    if len(images) != 1:
        sys.exit(f"expected 1 image, got {len(images)}")


STAGES = {
    "static": check_static,
    "pins": check_pins,
    "gpu": check_gpu,
    "render": check_render,
}


if __name__ == "__main__":
    stage = sys.argv[1] if len(sys.argv) > 1 else ""
    if stage not in STAGES:
        sys.exit(f"unknown stage {stage!r}; expected one of {', '.join(STAGES)}")
    STAGES[stage]()
