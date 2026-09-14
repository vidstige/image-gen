"""Power state of the one GPU VM, and its private address."""

from google.cloud import compute_v1

import config

RUNNING = "RUNNING"


def _client() -> compute_v1.InstancesClient:
    return compute_v1.InstancesClient()


def _instance() -> compute_v1.Instance:
    return _client().get(
        project=config.PROJECT, zone=config.ZONE, instance=config.VM_NAME
    )


def state() -> str:
    return _instance().status


def address() -> str:
    return _instance().network_interfaces[0].network_i_p


def start() -> None:
    _client().start(
        project=config.PROJECT, zone=config.ZONE, instance=config.VM_NAME
    )


def stop() -> None:
    _client().stop(
        project=config.PROJECT, zone=config.ZONE, instance=config.VM_NAME
    )
