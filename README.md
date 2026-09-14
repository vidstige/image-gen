# imgen

High-quality, uncensored image generation for one user, in the cloud, at
reasonable cost. A Cloud Run control plane behind Google login starts a
single GPU VM on demand, proxies generation to it, and lets it shut
itself down again; images land in a bucket that doubles as the gallery.

Built on diffusers and Flask, running on Google Cloud: Cloud Run for the
front door, one `a2-highgpu-1g` (A100 40GB) VM for the model, and Cloud
Storage for the images. There is no queue and no database — one GPU
serves one person serially, and object names carry the metadata.

    browser ──Google login (IAP)──► Cloud Run   [no GPU, scales to zero]
                                      │  starts/stops the VM, proxies
                                      ▼  (private VPC)
                                    GPU VM      [model resident in VRAM]
                                      │
                                      ▼
                                    bucket      (images + gallery)

## Layout

| file | what it holds |
| --- | --- |
| `config.py` | every tunable, imported by all three entry points |
| `pipeline.py` | model load and generation; no cloud, no HTTP |
| `storage.py` | bucket I/O and the object naming that carries metadata |
| `params_io.py` | JSON form of the generation parameters |
| `generate.py` | the CLI (M1) |
| `serve.py` | the HTTP API on the GPU box (M2) |
| `idle.py` | the idle timer that stops the VM (M3) |
| `control/` | the Cloud Run front end and VM power control (M4) |
| `infra/` | provisioning and deployment scripts |
| `m0/` | disposable model-comparison script |

## Running it

Pick a model first, on rented GPU time, before provisioning anything:

    ./m0/compare.py

Then set up the project, ship the code, create the VM and deploy the
front end. `HF_TOKEN` is needed because the weights are gated.

    ./infra/setup.sh
    ./infra/push.sh
    HF_TOKEN=hf_... ./infra/vm.sh
    ./infra/deploy.sh

One image from the command line, on the box:

    ./generate.py "a prompt" --seed 1 --out gs://your-project-images/test.png

Tests, which are CPU-only and take a second:

    pytest tests

## Costs

The GPU is the whole bill: about $3.75/hour while running, nothing while
stopped. It stops itself after ten idle minutes, the page shows the rate
before you start it, and a budget alert fires at $10, $18 and $20.

## Notes

The model loads once at process start and stays in VRAM — a per-request
load would be most of the latency. Nothing is quantised and no CPU
offload is used; the VRAM was bought so it would not have to be.

Guidance and negative-prompt arguments differ between pipelines, and a
dead argument is silently ignored, so `pipeline.supported` filters the
call against the actual signature rather than trusting sample code.
Prompts longer than the text encoder's limit are cut without warning,
so the token count and the limit are both shown in the UI.

The control plane's permission to start and stop the VM is a custom role
with exactly three permissions, bound to that one instance. The
predefined roles that would cover it grant far more.

## Two steps Google will not let a script do

**The IAP consent screen.** IAP is enabled on the Cloud Run service and
the account is allowlisted, but a project outside an Organization cannot
create its OAuth brand from the API — that API is shut down — so the
service answers 502 until the consent screen is configured once by hand
under *Google Auth Platform → Branding* in the Console. Nothing is
exposed in the meantime: unauthenticated requests do not reach the app.

**GPU quota.** A new project gets none, and the automated request is
denied for every card that matters. Appeal from *IAM & Admin → Quotas*
in the Console; new projects are usually approved once there is some
billing history.

## The card

Everything happens in europe-west4, which has all three candidates. The
design wants enough VRAM to run at native precision with no offload and
no quantisation, which rules out the 24 GB cards.

| card | VRAM | zones | quota |
| --- | --- | --- | --- |
| RTX PRO 6000 (`g4-standard-12`) | 96 GB | a, b, c, ai1a | denied |
| A100 40GB (`a2-highgpu-1g`) | 40 GB | a, b | denied |
| L4 (`g2-standard-8`) | 24 GB | a, b, c | granted, works today |

The RTX PRO 6000 is the one worth appealing for: 96 GB is more headroom
than the A100 has, and it is in more zones. Its quota is not the
obviously-named `NVIDIA-RTX-PRO-6000-VWS-GPUS` — that one is 1 by
default and is not what gets checked. The real limit is
`GPUS-PER-GPU-FAMILY-per-project-region` with `gpu_family:
NVIDIA_RTX_PRO_6000`, and it is 0. Only `europe-west4-ai1a` reports this
honestly; the ordinary zones fail with a stockout message first, which
hides the quota underneath it.

L4 quota is real: a `g2-standard-8` creates and runs today. Capacity
moves between zones — europe-west4-a and -b were stocked out while -c
had stock. But 24 GB will not hold FLUX.1-dev at bf16 without the
offload this design rules out, so taking it means choosing a smaller
model, which is an M0 decision rather than a deployment one.
