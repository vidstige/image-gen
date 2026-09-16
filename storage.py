"""Bucket I/O. Object names carry the metadata; there is no database."""

import io
import re
from datetime import datetime, timezone

from google.cloud import storage

import config
from params import Params

Location = tuple[str, str]  # bucket, object name

_SLUG = re.compile(r"[^a-z0-9]+")


def parse_uri(uri: str) -> Location:
    bucket, _, name = uri.removeprefix("gs://").partition("/")
    return bucket, name


def slug(prompt: str, limit: int = 48) -> str:
    return _SLUG.sub("-", prompt.lower()).strip("-")[:limit]


def name_for(params: Params, seed: int) -> str:
    """Sortable, self-describing: the listing is the gallery."""
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    return f"{stamp}-{seed:010d}-{slug(params.prompt)}.png"


def encode(image) -> bytes:
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()


def upload(image, params: Params, seed: int, uri: str = "") -> str:
    bucket_name, name = (
        parse_uri(uri) if uri else (config.BUCKET, name_for(params, seed))
    )
    blob = storage.Client().bucket(bucket_name).blob(name)
    blob.metadata = {
        "prompt": params.prompt,
        "negative_prompt": params.negative_prompt,
        "seed": str(seed),
        "steps": str(params.steps),
        "guidance": str(params.guidance),
        "size": f"{params.width}x{params.height}",
        "model": config.MODEL,
        "revision": config.MODEL_REVISION,
    }
    blob.upload_from_string(encode(image), content_type="image/png")
    return f"gs://{bucket_name}/{name}"


def gallery(limit: int = 60) -> list[dict]:
    """Newest first, with the parameters that made each image."""
    client = storage.Client()
    blobs = sorted(
        client.list_blobs(config.BUCKET),
        key=lambda b: b.time_created,
        reverse=True,
    )[:limit]
    return [
        {"name": b.name, "created": b.time_created.isoformat(),
         **(b.metadata or {})}
        for b in blobs
    ]


def delete(name: str) -> None:
    storage.Client().bucket(config.BUCKET).blob(name).delete()


def download(name: str) -> bytes:
    bucket = storage.Client().bucket(config.BUCKET)
    return bucket.blob(name).download_as_bytes()
