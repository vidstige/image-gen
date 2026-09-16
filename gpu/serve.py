"""HTTP API on the GPU box (M2).

Binds to the private interface only. No auth, because nothing outside the
VPC can route here. The model loads at import and stays in VRAM; a lock
serialises the one GPU.
"""

import threading
import time

from flask import Flask, jsonify, request

import config
import idle
import params_io
import pipeline
import storage

app = Flask(__name__)
lock = threading.Lock()
pipe = pipeline.load()
limit = pipeline.token_limit(pipe)


@app.get("/health")
def health():
    return jsonify(
        model=config.MODEL,
        revision=config.MODEL_REVISION,
        token_limit=limit,
        busy=lock.locked(),
        idle_seconds=round(idle.idle_seconds()),
    )


@app.post("/generate")
def generate():
    idle.touch()
    params = params_io.from_dict(request.get_json())
    started = time.monotonic()
    with lock:
        images = pipeline.generate(pipe, params)
    uris = [storage.upload(image, params, seed) for seed, image in images]
    idle.touch()
    return jsonify(
        images=[
            {"seed": seed, "uri": uri}
            for (seed, _), uri in zip(images, uris)
        ],
        tokens=pipeline.count_tokens(pipe, params.prompt),
        token_limit=limit,
        seconds=round(time.monotonic() - started, 1),
    )


idle.start()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=config.PORT, threaded=True)
