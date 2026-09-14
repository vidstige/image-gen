# Image generation service

**High-quality, uncensored image generation, for one user, in the cloud, at
reasonable cost.**

---

## What the goal forces

**Uncensored means self-hosted open weights.** Every hosted API filters, most
scan both the prompt and the output, and this is not a setting anyone exposes.
Open weights run on your own hardware have no filter — the filtering in a
vendor's product lives in the API layer, not in the weights. Some inference
libraries load an optional safety classifier alongside the pipeline; don't load
it.

This requirement, not price, is what justifies self-hosting. On cost alone a
hosted API wins at personal volumes and always will.

**High quality means enough VRAM to run at native precision.** The tempting
mistake is a smaller card plus aggressive quantisation; that is a visible
quality loss. Buy the VRAM instead. It also means the distilled speed variants
of a model are not the primary choice — they trade quality for latency.

**One user removes most of the infrastructure.** No queue, no autoscaling, no
database, no rate limiting. One GPU serves one person serially. Most complexity
in a generation service exists to handle concurrency that isn't present here.

**Reasonable cost means the GPU is off by default.** Idle time, not generation,
dominates the bill. This shapes the architecture and belongs in the design from
the start.

**Legal boundary**, stated once: sexual imagery of real identifiable people
without consent, and any sexual content involving minors, are criminal
regardless of where the compute runs.

---

## Google Cloud Project
Create a new Google Cloud Project for this named "your-gcp-project". Use my personal account "you@example.com". Feel free to spend a few dollars to test the service, but make the most of each test. Don't spend more than $20 for setting this up.

---

## Target architecture

```
browser ──Google login (IAP)──► Cloud Run service   [no GPU, scales to zero, ~free]
                                  │  starts/stops the VM, proxies generate calls
                                  ▼  (private VPC)
                                GPU VM  [model resident in VRAM, off by default]
                                  │
                                  ▼
                                object storage  (images)
```

**The Cloud Run service is the front door and the control plane.** It serves the
page, holds the login, and starts or stops the GPU. Having no GPU itself, it
scales to zero and costs essentially nothing to leave deployed permanently.
This is what allows the expensive half to be off by default.

**Google login comes from IAP on Cloud Run**, which guards the service URL
directly and requires no load balancer. This gives a real Google sign-in page
and an IAM allowlist with no authentication code written. Putting IAP in front
of a bare VM instead requires a managed instance group, an HTTPS load balancer,
a domain and a certificate.

**The GPU VM has no public IP**, reachable only from the Cloud Run service over
the VPC. Its own process needs no auth because nothing else can route to it.

**The model loads once at process start and stays in VRAM.** Generation takes
seconds, so a per-request load would be nearly all of the latency. Do not use
CPU-offload helpers; they exist for cards that are too small, which is the
situation the GPU criteria spend money to avoid.

**No queue.** Serialise with a single lock around the pipeline call. One GPU
processes one batch at a time regardless.

---

## Milestones

Each milestone has an exit test. Do not start the next one until the current
test passes. The order is chosen so that the two things most likely to kill the
project — inadequate output quality, and runaway cost — are settled before any
effort goes into the parts that are merely work.

### M0 — Prove the output clears the bar

**Before provisioning anything.** Rent an hour of GPU time interactively — a
spot instance or hosted notebook is fine, and this step is deliberately
disposable. Run two or three candidate models against 10–20 prompts
representative of actual intended use, not showcase prompts.

**Exit test:** a model is chosen, and there are images on disk that are good
enough to justify the project. Save the images locally for later inspection.

If nothing clears the bar, stop here. No amount of infrastructure improves
model output, and this is the cheapest possible point to discover that.

### M1 — A GPU box that generates on demand

Provision the VM, install drivers, download weights to local disk pinned to a
specific revision, and write a single CLI script that loads the model,
generates, and writes to the bucket. Trigger it manually over SSH.

**Exit test:**

```
./generate.py "a prompt" --seed 1 --out gs://bucket/test.png
```

writes a correct image to the bucket. Wall-clock time and cost per image are
known and recorded.

This is the whole product. Everything after it is access and convenience.

### M2 — An HTTP API on the box

Wrap the same code in a small HTTP service. Model loads at import and stays
resident; generation happens under a lock. Bind to the private interface, no
auth, no public IP.

**Exit test:** a `curl` from another host in the VPC returns an image, and **the
second call is dramatically faster than the first** — this is what proves the
model is actually resident rather than being reloaded.

### M3 — Start/stop and idle shutdown

Give the control plane permission to start and stop the VM. Add an idle timer
on the VM that shuts it down after N minutes without a request. Add a budget
alert.

**Exit test:** starting from a stopped VM, a start call brings it up, it serves
a request, and it then shuts *itself* down after the idle period — confirmed by
watching the instance state, not by reading the code.

Do this before the front end. An idle timer that silently fails is the most
expensive bug in this design, and it is much easier to verify in isolation.

### M4 — Front end with Google login

Deploy the Cloud Run service with IAP enabled and the intended account
allowlisted. It serves the page, proxies generate calls to the VM, and exposes
the VM's power state. The page carries prompt, negative prompt, seed, steps,
guidance, size, and a gallery built from the bucket listing.

**Exit test:** signing in with the allowlisted Google account works end to end
from a cold, stopped VM; **a different Google account is refused.** Verify the
refusal explicitly rather than assuming it.

### M5 — Quality pass

Only now tune. Add a prompt-expander, settle on step count and guidance, wire
up best-of-N. These are cheap to change and pointless to guess at before real
use.

---

## Quality knobs

Roughly in order of impact:

- **Prompt detail.** Dense, specific prompts beat every parameter change. An
  LLM prompt-expander in front of the input box is the highest-value feature
  available and takes a few lines.
- **Best-of-N.** Seed variance exceeds the effect of most settings. Generate
  four and keep one; a batch of four costs far less than four separate calls.
- **Guidance scale.** The main dial once prompts are good. Newer pipelines
  sometimes expose two differently-named guidance parameters, only one of which
  is live for a given model — read the pipeline signature rather than copying
  sample code.
- **Steps.** There is a knee, usually well below the library default, past
  which more steps buy nothing. Find it once.
- **Resolution.** Stay at or near native training resolution. Pushing well past
  it degrades composition rather than adding detail.
- **Negative prompt.** Start from the model's own published default, in its
  original language if it has one — translations land elsewhere in embedding
  space.
- **Seed.** Always set it, always log it, on every generation.

Do not quantise for speed.

---

## Known pitfalls

Specific failures observed on a closely comparable project.

- **Reloading weights per request.** The single most expensive mistake. In one
  case 29% of every request went to loading weights and shuffling a text
  encoder across PCIe, repeated every time. M2's exit test exists to catch this.
- **Least-privilege IAM bites in non-obvious ways.** Starting and stopping a VM
  from a service, or running a job with argument overrides, each need a
  specific narrow permission that the obvious predefined role does *not*
  include, while the roles that do include it grant far more than wanted. Use a
  custom role with exactly the needed permissions, bound to the one resource.
- **Unsurfaced cloud errors.** A missing IAM permission arrives as a generic
  500 with the real reason only in cloud logging. Add an error handler that
  returns the upstream exception type and message to the page. Without it,
  diagnosis starts in the wrong place and costs hours.
- **Library defaults are wrong for your model.** They are tuned for whatever
  shipped first. Take defaults from the model card.
- **Silent truncation.** Text encoders have a maximum sequence length; longer
  prompts are cut without warning. Know the limit and surface it in the UI.
- **Build the cost estimate into the UI**, shown before the expensive action
  runs. It changes behaviour in a way a monthly bill does not.
- **A CPU-only smoke test in the build** that imports the app, renders the page
  and asserts the form fields exist. Catches real breakage for a few seconds per
  build.
- **One configuration module** imported by every entry point, so the CLI, the
  API and the front end cannot drift apart.

---

## Out of scope

Until something actually hurts:

- A graph-based generation UI — it will be driven from code anyway
- A job queue or message bus — one GPU serialises regardless
- A database — the bucket listing is the gallery; object names carry metadata
- Autoscaling, multi-region, multi-model serving
- Hand-rolled authentication
- LoRA training or fine-tuning — LoRAs from the ecosystem get most of the way
  for a fraction of the effort

