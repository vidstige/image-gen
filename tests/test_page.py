"""CPU-only smoke test: the app imports and the page has its form."""

import json

import main


def test_page_renders_with_every_form_field():
    page = main.app.test_client().get("/").data.decode()
    for field in ("prompt", "negative_prompt", "seed", "steps",
                  "guidance", "width", "height", "count"):
        assert f'id="{field}"' in page


def test_page_carries_defaults_as_json():
    page = main.app.test_client().get("/").data.decode()
    assert "__DEFAULTS__" not in page
    assert json.dumps(main.defaults()) in page
