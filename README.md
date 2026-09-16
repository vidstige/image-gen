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
| `params.py` | the knobs one generation takes |
| `storage.py` | bucket I/O and the object naming that carries metadata |
| `gpu/pipeline.py` | model load and generation; no cloud, no HTTP |
| `gpu/params_io.py` | JSON form of the generation parameters |
| `gpu/generate.py` | the CLI (M1) |
| `gpu/serve.py` | the HTTP API on the GPU box (M2) |
| `gpu/idle.py` | the idle timer that stops the VM (M3) |
| `control/` | the Cloud Run front end and VM power control (M4) |
| `infra/` | provisioning and deployment scripts |
| `m0/` | disposable model-comparison script |

The three files at the root are the ones both halves need. Everything
under `gpu/` is what `push.sh` ships to the box and nothing else goes
there; everything under `control/` is what the Cloud Run image gets.
`Params` lives in its own module so the front end can talk about a
generation without importing the model code.

## Configuration

Everything that names a particular project lives in `.env`, which is not
committed, so the rest of the repo is publishable as it stands. Copy the
example and fill it in:

    cp .env.example .env

`config.py` reads it, `infra/env.sh` sources it for the shell scripts,
`deploy.sh` passes the values to Cloud Run as environment variables, and
`push.sh` ships it to the GPU VM alongside the source. The one thing
that cannot travel that way is the name of the bucket the source comes
from, so `vm.sh` puts that in instance metadata.

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

Power the GPU on or off by hand, and see where it is:

    ./infra/power.sh status
    ./infra/power.sh on
    ./infra/power.sh off

The page does the same thing: a lamp and a start/stop button together at
the top, polled every five seconds, amber while it is starting, loading
the model or stopping, and green once it is actually serving. Generating
starts the VM on its own if it is off.

Beside the lamp it says whether the box is idle or generating, which is
the server's lock rather than a guess. While anything is moving the page
polls every five seconds and the gallery picks up finished images on its
own; once everything has settled it stops asking. That matters because a
generate request can easily outlive its own connection when the VM has
to boot first, and waiting for it to return was losing pictures that had
in fact been made. The loop therefore runs on the server's busy flag,
not on this page's request surviving.

The negative prompt is kept in the browser between visits. Note that the
model's own published default is a single space; the default here is an
ordinary English one, which is a deliberate departure.

Clicking any image in the gallery opens it with the prompt, seed, steps,
guidance, size, model and date it was made, and buttons to download or
delete it.

One image from the command line, on the box:

    cd /opt/imgen && PYTHONPATH=. /opt/venv/bin/python gpu/generate.py \
      "a prompt" --seed 1 --out gs://$IMGEN_BUCKET/test.png

Tests, which are CPU-only and take a second:

    pytest tests

## Costs

The GPU is the whole bill, and nothing but the disk costs anything while
it is stopped. It stops itself after five idle minutes, and a budget
alert fires at 50%, 90% and 100% of 200 SEK.

At the time of writing a spot `g4-standard-48` was about $2.08/hour, so
an image at the default 50 steps — 48 seconds — cost around three cents.
That number is not in the code or the page: a hard-coded price goes
stale silently, which is worse than no price at all. Check the current
one against the billing catalogue, or the budget alert.

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

**The IAP OAuth client.** IAP is enabled on the Cloud Run service and
the account is allowlisted, but IAP needs an OAuth client to run the
sign-in, and it has none, so the service answers 502 with *Empty Google
Account OAuth client ID(s)/secret(s)*. The Google-managed client IAP
would normally use exists only for projects inside an organisation, and
OAuth clients cannot be created through any API — the IAP OAuth Admin
APIs were shut down in March 2026. So one client has to be made by hand
in the console, once. Then:

    ./infra/iap.sh CLIENT_ID CLIENT_SECRET

Nothing is exposed in the meantime: unauthenticated requests do not
reach the app.

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

## Where the milestones stand

**M0 — output clears the bar.** Qwen-Image, ungated and Apache-2.0, with
no safety classifier. Photoreal work is strong: skin texture, hands, fur,
rim light and atmosphere all hold up at 1328x1328 and 50 steps. Text
inside an image does not; a prompt asking for labels gets confident
gibberish. Images in `m0/` and in the bucket.

**M1 — a box that generates on demand.** `./generate.py "..." --seed 1
--out gs://.../test.png` writes a correct image. 48 seconds of denoising
at 1.03 it/s, no offload, so about three cents an image.

**M2 — an HTTP API.** `curl` from another host in the VPC returns an
image. The model is resident rather than reloaded: between requests one
process holds 65 GB of the 97 GB card. Note that the exit test as
written — second call much faster than the first — cannot show this
here, because the model loads at import during boot, so the *first* API
call is already warm. Both calls take 50 s, of which 48 s is the
denoising loop. The VRAM held while idle is the direct evidence.

**M3 — start/stop and idle shutdown.** Verified by watching instance
state, not by reading code: last request 22:07, `STOPPING` at 22:17,
`TERMINATED` at 22:18. It has since done the same thing unattended after
a batch. A 200 SEK budget alert is in place.

**M4 — front end.** Deployed with IAP on and the account allowlisted,
but see the consent screen note above; it answers 502 until that is done
by hand, so the sign-in and the refusal of a second account are both
still unverified.

## The card

`g4-standard-48` gets the whole 96 GB card. The smaller g4 shapes get a
48 GB vGPU slice instead, which is not something the machine type
advertises and not enough for this model — it needs about 55 GB for the
transformer and text encoder together. Three further things are not
guessable: G4 rejects `pd-balanced` and needs `hyperdisk-balanced`; the
`pytorch-latest-gpu` image family no longer exists; and Blackwell needs
the R580 branch with its *open* kernel module, built with gcc-12 because
that is what the 6.8 kernel was built with.

On-demand quota for this card is denied, on a new project and on an old
one with billing history alike, so the VM is spot. That suits a design
whose GPU is off by default anyway: preemption mostly means it turned
off early, and the instance stops rather than being deleted, so the
weights on its disk survive.
