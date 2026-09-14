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

**A100 quota.** A new project gets no GPU quota, and the automated
request for one A100 in europe-west4 came back *Quota request denied* —
as did us-central1. `GPUS_ALL_REGIONS` was granted. Appeal from *IAM &
Admin → Quotas* in the Console; new projects are usually approved once
there is some billing history. `infra/vm.sh` works as soon as it lands.

The alternative is an L4, whose quota is 1 by default. It has 24 GB, so
FLUX.1-dev will not fit at bf16 without the offload this design rules
out — taking it means picking a smaller model, and that is an M0
decision, not a deployment one.
