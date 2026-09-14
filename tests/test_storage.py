from storage import name_for, parse_uri, slug
from pipeline import Params


def params(prompt: str = "a red fox") -> Params:
    return Params(prompt=prompt)


def test_uri_splits_into_bucket_and_object():
    assert parse_uri("gs://b/dir/test.png") == ("b", "dir/test.png")


def test_slug_keeps_only_lowercase_words():
    assert slug("A Red Fox, at dusk!") == "a-red-fox-at-dusk"


def test_names_sort_by_time_then_seed():
    names = [name_for(params(), seed) for seed in (2, 10)]
    assert names == sorted(names)


def test_name_carries_prompt_and_seed():
    name = name_for(params(), 7)
    assert "0000000007" in name and "a-red-fox" in name
