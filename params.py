"""The knobs one generation takes. Shared by the box and the front end."""

from dataclasses import dataclass

import config


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
