# imgen

High-quality, uncensored image generation for one user, in the cloud, at
reasonable cost. A Cloud Run control plane behind Google login starts a
single GPU VM on demand, proxies generation to it, and lets it shut
itself down again; images land in a bucket that doubles as the gallery.

Built on diffusers and Flask, running on Google Cloud: Cloud Run for the
front door, one spot `g4-standard-12` (RTX PRO 6000, 96 GB) VM for the
model, and Cloud Storage for the images. There is no queue and no database — one GPU
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

    ./infra/setup.sh    # once per project: network, buckets, IAM, budget
    ./infra/push.sh     # ship the code the VM runs
    ./infra/vm.sh       # create the GPU VM
    ./infra/deploy.sh   # build and deploy the front end

`vm.sh` needs nothing but `push.sh` having run first. The VM installs
its own driver, builds its venv, downloads the weights and starts
serving, all from `infra/startup.sh`, which runs on every boot and skips
whatever is already on the disk. The first boot takes about twenty
minutes, almost all of it the 54 GB of weights; later boots take about a
minute. To ship new server code afterwards, `./infra/push.sh` uploads it
and restarts the VM into it.

One image from the command line, on the box:

    ./generate.py "a prompt" --seed 1 --out gs://your-project-images/test.png

Tests, which are CPU-only and take a second:

    pytest tests

## Costs

The GPU is the whole bill: about $2.08/hour while running, nothing while
stopped except the disk. It stops itself after ten idle minutes, the page
shows the rate before you start it, and a budget alert fires at 50%, 90%
and 100% of 200 SEK.

That figure is the spot price from the billing catalogue: 48 vCPU at
$0.02232, 180 GiB at $0.00268 and one card at $0.52640 per hour. An
image at the default 50 steps takes 48 seconds, so it costs about three
cents.

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

Everything runs in europe-west4. The design wants enough VRAM for native
precision with no offload and no quantisation, which rules out the 24 GB
cards, and on-demand quota for everything larger is denied — on a new
project and on an old one with years of billing alike, so it is not
about history. Appealing through the API is denied too.

Spot draws on a different pool and works today. That suits this design:
the VM is already off by default, already started on demand, and already
stops itself when idle, so preemption mostly means it turned off early.
It is set to stop rather than be deleted, so the weights on its disk
survive.

| card | VRAM | on-demand | spot |
| --- | --- | --- | --- |
| RTX PRO 6000 (`g4-standard-12`) | 96 GB | denied | **works** |
| A100 40GB (`a2-highgpu-1g`) | 40 GB | denied | — |
| L4 (`g2-standard-8`) | 24 GB | granted, too small | — |

Three things about this card are not guessable from the machine type.
G4 rejects `pd-balanced` and needs `hyperdisk-balanced`. The
`pytorch-latest-gpu` image family no longer exists; the current one is
`common-cu129-ubuntu-2204-nvidia-580`. And only `europe-west4-ai1a` has
capacity, where the card is presented as a vGPU that the base image's
open kernel module refuses to drive — hence the GRID driver install in
`infra/startup.sh`.

If the quota is ever granted, moving back to on-demand is one flag in
`infra/vm.sh`.

## M0 result

Four images from Qwen-Image are in the bucket and in `m0/`. The model is
ungated, Apache-2.0, and carries no safety classifier, which is why it
was chosen over FLUX.1-dev without a HuggingFace token.

Photoreal work clears the bar comfortably: skin texture, hands, fog and
raking light all hold up at 1328x1328 and 50 steps. Line art is clean.
Text inside an image is not reliable, and a prompt asking for labels
gets confident gibberish, so treat legible text as out of reach until
tested properly.

One hard constraint the machine type does not advertise: `g4-standard-24`
reports a 48 GB vGPU slice, not the card's full 96 GB. Qwen-Image needs
about 55 GB for the transformer and text encoder together, so it does
not fit and these four were generated with CPU offload, which the design
otherwise rules out. Either a shape that exposes the whole card or a
model that fits 48 GB is needed before M1 is really passed.
