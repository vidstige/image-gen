"""Shared configuration. Imported by the CLI, the API and the front end.

Everything that names a particular project lives in a local .env, so
this file carries only settings worth publishing.
"""

import os
from pathlib import Path


def _load(path: Path) -> None:
    for line in path.read_text().splitlines():
        name, _, value = line.partition("=")
        if name.strip() and not name.startswith("#"):
            os.environ.setdefault(name.strip(), value.strip())


_env = Path(__file__).with_name(".env")
if _env.exists():
    _load(_env)

PROJECT = os.environ["IMGEN_PROJECT"]
REGION = "europe-west4"
ZONE = "europe-west4-ai1a"
NETWORK = "imgen"
SUBNET = "imgen"

VM_NAME = "imgen-gpu"
VM_TYPE = "g4-standard-48"
VM_ACCELERATOR = "type=nvidia-rtx-pro-6000,count=1"
VM_DISK_GB = 200

BUCKET = os.environ["IMGEN_BUCKET"]
PORT = 8000

# Smaller g4 shapes get a 48 GB vGPU slice; this one gets the whole
# 96 GB card, which is what lets the model run without offload.
IDLE_MINUTES = 5

# Pinned to a revision so weights cannot change under us. Defaults below are
# from the model card, not from the library.
MODEL = "Qwen/Qwen-Image"
MODEL_REVISION = "75e0b4be04f60ec59a75f475837eced720f823b6"
STEPS = 50
GUIDANCE = 4.0
# Qwen-Image takes both guidance_scale and true_cfg_scale, and only the
# latter is live; the other silently does nothing. Name the live one.
GUIDANCE_PARAM = "true_cfg_scale"
WIDTH = 1328
HEIGHT = 1328
NEGATIVE_PROMPT = (
    "worst quality, low quality, blurry, jpeg artifacts, 3d render, "
    "bad anatomy, text, watermark"
)
BATCH = 4
