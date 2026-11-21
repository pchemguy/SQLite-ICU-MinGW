"""Exercise build handoff and shared-library replacement without a package download."""

import os
from pathlib import Path
import shutil
import subprocess
import sys

import pytest


BASE = Path(__file__).resolve().parents[1]


@pytest.fixture(scope="module")
def shared_sqlite_python():
    probe = """import sqlite3, venv
print(next((line.split(maxsplit=5)[5].strip() for line in open('/proc/self/maps')
            if '/libsqlite3.so' in line), ''))
"""
    for python in dict.fromkeys((sys.executable, shutil.which("python3", path=os.defpath))):
        if python:
            result = subprocess.run([python, "-I", "-c", probe], capture_output=True, text=True)
            if result.returncode == 0 and Path(result.stdout.strip()).is_file():
                return python, result.stdout.strip()
    pytest.skip("Requires a Linux Python with a dynamically linked SQLite and venv")


@pytest.fixture
def wrapper(tmp_path, shared_sqlite_python):
    python, stock_sqlite = shared_sqlite_python
    harness = tmp_path / "harness"
    bundle = harness / "tool" / "conda_env"
    bundle.mkdir(parents=True)
    entry = harness / "sqlite_build_conda.sh"
    shutil.copy2(BASE / entry.name, entry)
    shutil.copy2(BASE / "tool/build_root.sh", bundle.parent)
    for name in ("Anaconda_bootstrap.yml", "Anaconda.yml", "Anaconda.txt"):
        (bundle / name).write_text(name)
    (bundle / "Anaconda.sh").write_text("""#!/bin/bash
set -eu
prefix=${0%.sh}
test "$prefix" = "$OUT_DIR/conda"
test "$(cat "${prefix}_bootstrap.yml")" = Anaconda_bootstrap.yml
test "$(cat "${prefix}.yml")" = Anaconda.yml
test "$(cat "${prefix}.txt")" = Anaconda.txt
echo bootstrap >> "$EVENTS"
if [[ ! -x $prefix/bin/python ]]; then
  "$TEST_PYTHON" -m venv --without-pip "$prefix"
  mkdir -p "$prefix/conda-meta" "$prefix/lib"
  touch "$prefix/conda-meta/history"
  ln "$ORIGINAL" "$prefix/lib/libsqlite3.so.stock"
  ln -s libsqlite3.so.stock "$prefix/lib/libsqlite3.so.0"
  ln -s libsqlite3.so.0 "$prefix/lib/libsqlite3.so"
fi
exit "${BOOT_STATUS:-0}"
""")
    driver = harness / "sqlite_build.sh"
    driver.write_text("""#!/bin/bash
set -eu
if [[ ${1:-} == --check-preset ]]; then exec "$REAL_DRIVER" "$@"; fi
out=$OUT_DIR
source "$(dirname "$0")/tool/build_root.sh"
lock_output_root
test -x "$out/conda/bin/python"
test ! -e "$out/build"
test ! -e "$out/bin" && test ! -L "$out/bin"
test "$#" = 2 && test "$1" = --preset
echo "build $2" >> "$EVENTS"
if [[ -n ${BUILD_STATUS:-} ]]; then exit "$BUILD_STATUS"; fi
mkdir -p "$out/build" "$out/lib" "$out/package/bin"
ln -s package/bin "$out/bin"
cp "$ORIGINAL" "$out/lib/libsqlite3.so.0"
printf '%s' "$2" >> "$out/lib/libsqlite3.so.0"
""")
    driver.chmod(0o755)
    root = tmp_path / "out"
    root.mkdir()
    original = tmp_path / "stock-cache-library"
    shutil.copy2(stock_sqlite, original)
    env = dict(os.environ, OUT_DIR=str(root), EVENTS=str(tmp_path / "events"),
               REAL_DRIVER=str(BASE / "sqlite_build.sh"), TEST_PYTHON=python, ORIGINAL=str(original),
               LD_LIBRARY_PATH=str(root / "conda/lib"))

    def run(*args, **overrides):
        return subprocess.run([entry, *args], cwd=tmp_path, env=dict(env, **overrides),
                              capture_output=True, text=True, timeout=30)

    return root, original, run


def test_cold_build_and_reuse(wrapper):
    root, original, run = wrapper
    cache = root / "cache"
    cache.mkdir()
    (cache / "keep").touch()
    (root / "build").mkdir()
    (root / "build/old").touch()
    (root / "bin").symlink_to(cache, target_is_directory=True)
    stock = original.read_bytes()
    result = run("--preset", "bare-icu-ext")
    assert result.returncode == 0, result.stderr
    target = root / "conda/lib/libsqlite3.so.stock"
    assert str(target) in result.stdout
    assert (root / "conda/lib/libsqlite3.so").resolve() == target
    assert not target.samefile(original)
    assert target.read_bytes() == stock + b"bare-icu-ext"
    assert (cache / "keep").exists() and not (root / "build/old").exists()
    assert not (root / "conda.sh").exists()
    assert run().returncode == 0
    assert (root.parent / "events").read_text().splitlines() == [
        "bootstrap", "build bare-icu-ext", "build full"]
    assert target.read_bytes() == stock + b"full" and original.read_bytes() == stock


def test_wrong_loaded_library_restores_original(wrapper):
    root, original, run = wrapper
    result = run("--preset", "bare", LD_LIBRARY_PATH="")
    assert result.returncode and "Expected Python to load" in result.stderr
    assert (root / "conda/lib/libsqlite3.so.0").samefile(original)
    assert not list((root / "conda/lib").glob(".sqlite-install.*"))


def test_bootstrap_and_build_failures(wrapper):
    root, original, run = wrapper
    (root / "build").mkdir()
    (root / "build/keep").touch()
    invalid = run("--preset", "unknown")
    assert invalid.returncode and "Unknown preset" in invalid.stderr
    assert not (root / ".sqlite-gcc-root").exists() and not (root.parent / "events").exists()
    assert not (root / "conda").exists()
    assert run("--preset", "bare", BOOT_STATUS="42").returncode == 42
    assert (root / "build/keep").exists()
    assert (root / "conda/bin/python").is_file()
    (root / "package/bin").mkdir(parents=True)
    (root / "bin").symlink_to("package/bin")
    assert run("--preset", "bare", BUILD_STATUS="73").returncode == 73
    assert (root / "bin").readlink() == Path("package/bin")
    assert (root / "conda/lib/libsqlite3.so.0").samefile(original)
    assert (root.parent / "events").read_text().splitlines() == ["bootstrap", "bootstrap", "build bare"]
