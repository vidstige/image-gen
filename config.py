"""Shared configuration. Imported by the CLI, the API and the front end."""

PROJECT = "your-gcp-project"
REGION = "europe-west4"
ZONE = "europe-west4-a"
NETWORK = "imgen"
SUBNET = "imgen"

VM_NAME = "imgen-gpu"
VM_TYPE = "a2-highgpu-1g"
VM_ACCELERATOR = "type=nvidia-tesla-a100,count=1"
VM_DISK_GB = 200

BUCKET = "your-project-images"
PORT = 8000

# A100 40GB on-demand, europe-west4, USD per hour. Shown in the UI so the
# price of the expensive action is visible before it is taken.
VM_COST_PER_HOUR = 3.75
IDLE_MINUTES = 10

# Pinned to a revision so weights cannot change under us. Defaults below are
# from the model card, not from the library.
MODEL = "black-forest-labs/FLUX.1-dev"
MODEL_REVISION = "0ef5fff789c832c5c7f4e127f94c8b54bbcced44"
STEPS = 28
GUIDANCE = 3.5
WIDTH = 1024
HEIGHT = 1024
NEGATIVE_PROMPT = ""
BATCH = 4
