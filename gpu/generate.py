#!/usr/bin/env python3
"""CLI for one-off generation on the GPU box (M1)."""

import argparse

import config
import pipeline
import storage


def parse_args() -> tuple[pipeline.Params, str]:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("prompt")
    parser.add_argument("--negative", default=config.NEGATIVE_PROMPT)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--steps", type=int, default=config.STEPS)
    parser.add_argument("--guidance", type=float, default=config.GUIDANCE)
    parser.add_argument("--width", type=int, default=config.WIDTH)
    parser.add_argument("--height", type=int, default=config.HEIGHT)
    parser.add_argument("--count", type=int, default=1)
    parser.add_argument("--out", default="")
    args = parser.parse_args()
    params = pipeline.Params(
        prompt=args.prompt,
        negative_prompt=args.negative,
        seed=args.seed,
        steps=args.steps,
        guidance=args.guidance,
        width=args.width,
        height=args.height,
        count=args.count,
    )
    return params, args.out


def main() -> None:
    params, out = parse_args()
    pipe = pipeline.load()
    limit = pipeline.token_limit(pipe)
    tokens = pipeline.count_tokens(pipe, params.prompt)
    if tokens > limit:
        print(f"warning: prompt cut at {limit} of {tokens} tokens")
    for seed, image in pipeline.generate(pipe, params):
        print(storage.upload(image, params, seed, out))


if __name__ == "__main__":
    main()
