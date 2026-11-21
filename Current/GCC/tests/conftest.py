from pathlib import Path

import pytest


def pytest_addoption(parser):
    parser.addoption("--build-root", type=Path, help="Dedicated output root reused by the native build tests.")


@pytest.fixture(scope="session")
def build_root(pytestconfig, tmp_path_factory):
    requested = pytestconfig.getoption("--build-root")
    return requested.resolve() if requested else tmp_path_factory.mktemp("gcc-build")
