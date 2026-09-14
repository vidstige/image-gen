"""Shared configuration. Imported by the CLI, the API and the front end."""

PROJECT = "your-gcp-project"
REGION = "europe-west4"
ZONE = "europe-west4-ai1a"
NETWORK = "imgen"
SUBNET = "imgen"

VM_NAME = "imgen-gpu"
VM_TYPE = "g4-standard-12"
VM_ACCELERATOR = "type=nvidia-rtx-pro-6000,count=1"
VM_DISK_GB = 200

BUCKET = "your-project-images"
PORT = 8000

# Shown in the UI so the price of the expensive action is visible before
# it is taken. Spot, europe-west4, from the billing catalogue:
# 12 vCPU x 0.02232 + 45 GiB x 0.00268 + one card at 0.52640.
VM_COST_PER_HOUR = 0.92
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
