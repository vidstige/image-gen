#!/usr/bin/env python3
"""M0: run candidate models over real prompts on rented GPU time.

Disposable by design. Writes m0/<model>/<n>-<seed>.png for inspection.
"""

import sys
from pathlib import Path

import torch
from diffusers import DiffusionPipeline

CANDIDATES = [
    "black-forest-labs/FLUX.1-dev",
    "Qwen/Qwen-Image",
    "stabilityai/stable-diffusion-3.5-large",
]
SEEDS = [1, 2]


def prompts() -> list[str]:
    path = Path(__file__).with_name("prompts.txt")
    lines = path.read_text().splitlines()
    return [l for l in lines if l.strip() and not l.startswith("#")]


def run(model: str) -> None:
    out = Path(__file__).parent / model.split("/")[-1]
    out.mkdir(exist_ok=True)
    pipe = DiffusionPipeline.from_pretrained(
        model, torch_dtype=torch.bfloat16
    ).to("cuda")
    for n, prompt in enumerate(prompts()):
        for seed in SEEDS:
            generator = torch.Generator("cuda").manual_seed(seed)
            image = pipe(prompt=prompt, generator=generator).images[0]
            image.save(out / f"{n:02d}-{seed}.png")
            print(out / f"{n:02d}-{seed}.png")
    del pipe
    torch.cuda.empty_cache()


if __name__ == "__main__":
    for model in sys.argv[1:] or CANDIDATES:
        run(model)
