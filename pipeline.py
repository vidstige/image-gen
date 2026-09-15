"""Model loading and image generation. No cloud, no HTTP, no filtering."""

import inspect
from dataclasses import dataclass

import config

Size = tuple[int, int]


@dataclass
class Params:
    prompt: str
    negative_prompt: str = config.NEGATIVE_PROMPT
    seed: int = 0
    steps: int = config.STEPS
    guidance: float = config.GUIDANCE
    width: int = config.WIDTH
    height: int = config.HEIGHT
    count: int = 1


def load():
    """Load once at process start. The model then stays in VRAM."""
    import torch
    from diffusers import DiffusionPipeline

    pipe = DiffusionPipeline.from_pretrained(
        config.MODEL,
        revision=config.MODEL_REVISION,
        torch_dtype=torch.bfloat16,
        # The whole point of self-hosting. Never load the classifier.
        safety_checker=None,
        requires_safety_checker=False,
    )
    return pipe.to("cuda")


def token_limit(pipe) -> int:
    """Prompt tokens the pipeline keeps. Longer prompts are cut.

    The tokenizer's own `model_max_length` is not the answer: Qwen2's is
    131072 while the pipeline truncates at its `max_sequence_length`
    default, two orders of magnitude lower. Take the pipeline's.
    """
    sequence = inspect.signature(pipe.__call__).parameters.get(
        "max_sequence_length"
    )
    if sequence is not None and sequence.default is not inspect.Parameter.empty:
        return sequence.default
    return min(
        t.model_max_length
        for t in (pipe.tokenizer, getattr(pipe, "tokenizer_2", None))
        if t is not None
    )


def count_tokens(pipe, prompt: str) -> int:
    return len(pipe.tokenizer(prompt).input_ids)


def supported(pipe, **kwargs) -> dict:
    """Keep only arguments this pipeline actually takes.

    Pipelines differ in which guidance and negative-prompt arguments are
    live; passing a dead one silently does nothing. Read the signature
    instead of copying sample code.
    """
    accepted = inspect.signature(pipe.__call__).parameters
    return {k: v for k, v in kwargs.items() if k in accepted}


def generate(pipe, params: Params) -> list[tuple[int, object]]:
    """Generate one batch, returning (seed, image) per image.

    One generator per image keeps every seed individually reproducible
    while still costing a single batched call.
    """
    import torch

    seeds = list(range(params.seed, params.seed + params.count))
    generators = [
        torch.Generator("cuda").manual_seed(seed) for seed in seeds
    ]
    arguments = supported(
        pipe,
        prompt=params.prompt,
        negative_prompt=params.negative_prompt or None,
        num_inference_steps=params.steps,
        width=params.width,
        height=params.height,
        num_images_per_prompt=params.count,
        generator=generators,
        **{config.GUIDANCE_PARAM: params.guidance},
    )
    return list(zip(seeds, pipe(**arguments).images))
