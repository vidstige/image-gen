# Mirrors config.py. Sourced by every script in this directory.
PROJECT=your-gcp-project
REGION=europe-west4
ZONE=europe-west4-a
NETWORK=imgen
SUBNET=imgen
VM=imgen-gpu
VM_TYPE=a2-highgpu-1g
ACCELERATOR=type=nvidia-tesla-a100,count=1
DISK_GB=200
BUCKET=your-project-images
CODE=your-project-code
SERVICE=imgen
PORT=8000
USER_ACCOUNT=you@example.com
BUDGET=200SEK   # the billing account is in SEK; ~$20
