"""Runtime checks, run inside the container as `python - <stage>`.

Split by stage so the checks that need no GPU can run on their own.
"""

import json
import os
import re
import sys


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

    # Set by uv because requirements.in pins xformers by URL. A PyPI xformers of the same version
    # is built against another CUDA and would fail here anyway.

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


STAGES = {
    "static": check_static,
    "pins": check_pins,
    "gpu": check_gpu,
}


if __name__ == "__main__":
    stage = sys.argv[1] if len(sys.argv) > 1 else ""
    if stage not in STAGES:
        sys.exit(f"unknown stage {stage!r}; expected one of {', '.join(STAGES)}")
    STAGES[stage]()
