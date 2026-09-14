import config
from pipeline import Params, supported


class FakePipe:
    def __call__(self, prompt, guidance_scale, generator):
        pass


def test_unsupported_arguments_are_dropped():
    kept = supported(
        FakePipe(), prompt="a", guidance_scale=3.5, true_cfg_scale=1.0
    )
    assert kept == {"prompt": "a", "guidance_scale": 3.5}


def test_defaults_come_from_the_shared_config():
    params = Params(prompt="a")
    assert (params.steps, params.guidance) == (config.STEPS, config.GUIDANCE)
