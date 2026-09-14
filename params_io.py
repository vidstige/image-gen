"""JSON form of generation parameters, shared by the API and the UI."""

from dataclasses import asdict

import config
from pipeline import Params


def from_dict(payload: dict) -> Params:
    return Params(
        prompt=payload["prompt"],
        negative_prompt=payload.get("negative_prompt", config.NEGATIVE_PROMPT),
        seed=int(payload.get("seed", 0)),
        steps=int(payload.get("steps", config.STEPS)),
        guidance=float(payload.get("guidance", config.GUIDANCE)),
        width=int(payload.get("width", config.WIDTH)),
        height=int(payload.get("height", config.HEIGHT)),
        count=int(payload.get("count", config.BATCH)),
    )


def to_dict(params: Params) -> dict:
    return asdict(params)
