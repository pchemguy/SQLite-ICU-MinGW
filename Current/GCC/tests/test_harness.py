import os
from pathlib import Path
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from zipfile import ZipFile

import pytest


BASE = Path(__file__).resolve().parents[1]
SOURCES = BASE / "tool/sources.sh"
DEPENDENCIES = BASE / "tool/dependencies.sh"


def shell(script, *args, env=None):
    return subprocess.run(["/bin/bash", "-euc", 'die() { echo "$*" >&2; exit 1; }\n' + script,
                           "test", *map(str, args)], env=env, capture_output=True, text=True)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.server.calls.append(self.path)
        if self.path == "/redirect":
            self.send_response(302)
            self.send_header("Location", "/ok")
            self.end_headers()
            return
        code = {"/partial": 206, "/missing": 404}.get(self.path, 200)
        body = b"source"
        self.send_response(code)
        self.send_header("Content-Type", "TeXt/HTML ; charset=utf-8" if self.path == "/html" else "application/octet-stream")
        self.send_header("Content-Length", str(len(body) + (3 if self.path == "/short" else 0)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


@pytest.fixture
def server():
    http = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    http.calls = []
    thread = threading.Thread(target=http.serve_forever, daemon=True)
    thread.start()
    try:
        yield f"http://127.0.0.1:{http.server_port}", http.calls
    finally:
        http.shutdown()
        thread.join()
        http.server_close()


@pytest.mark.parametrize("bad", ["html", "partial", "missing", "short"])
def test_download_rejects_then_recovers(tmp_path, server, bad):
    url, calls = server
    target = tmp_path / "cache/input"
    script = 'source "$1"; work=$2; download "$3" "$4"'
    assert shell(script, SOURCES, tmp_path, f"{url}/{bad}", target).returncode
    assert not target.exists()
    recovered = shell(script, SOURCES, tmp_path, f"{url}/redirect", target)
    assert recovered.returncode == 0, recovered.stderr
    assert target.read_bytes() == b"source"
    count = len(calls)
    assert shell(script, SOURCES, tmp_path, f"{url}/missing", target).returncode == 0
    assert len(calls) == count


def test_archive_requires_complete_source_root(tmp_path):
    archive = tmp_path / "src.zip"
    script = 'shopt -s nullglob; source "$1"; unpack_zip "$2" "$3" configure main.mk'
    with ZipFile(archive, "w") as zipfile:
        zipfile.writestr("sqlite/configure", "configure")
    assert shell(script, SOURCES, archive, tmp_path / "incomplete").returncode
    with ZipFile(archive, "a") as zipfile:
        zipfile.writestr("sqlite/main.mk", "rules")
    ok = shell(script, SOURCES, archive, tmp_path / "valid")
    assert ok.returncode == 0 and Path(ok.stdout.strip()).name == "sqlite"
    with ZipFile(archive, "a") as zipfile:
        zipfile.writestr("second/file", "data")
    assert shell(script, SOURCES, archive, tmp_path / "ambiguous").returncode


@pytest.mark.parametrize(("manager", "packages"), [
    ("apt-get", "libicu-dev zlib1g-dev"), ("dnf", "libicu-devel pkgconfig(zlib)")])
def test_install_only_missing_dependencies(tmp_path, manager, packages):
    def command(name, body):
        path = tmp_path / name
        path.write_text("#!/bin/sh\n" + body)
        path.chmod(0o755)

    command("sudo", 'exec "$@"\n')
    command("pkg-config", 'test -f "$STATE"\n')
    command(manager, """echo "$*" >> "$CALLS"
if test "$1" = install; then
    test "$FAIL" = 0 || exit 42
    : > "$STATE"
fi
""")
    calls = tmp_path / "calls"
    env = dict(os.environ, PATH=str(tmp_path), STATE=str(tmp_path / "present"), CALLS=str(calls), FAIL="0")
    script = 'source "$1"; USE_ICU=$2; SQLITE_EXTRA=$3; ensure_dependencies'
    assert shell(script, DEPENDENCIES, 0, 0, env=env).returncode == 0
    assert not calls.exists()
    assert shell(script, DEPENDENCIES, 1, 1, env=dict(env, FAIL="1")).returncode
    calls.unlink()
    for _ in range(2):
        result = shell(script, DEPENDENCIES, 1, 1, env=env)
        assert result.returncode == 0, result.stderr
    installs = [line for line in calls.read_text().splitlines() if line.startswith("install ")]
    assert len(installs) == 1 and installs[0].endswith(packages)


@pytest.mark.parametrize(("arguments", "settings", "reason"), [
    (["--preset", "unknown"], {}, "Unknown preset"),
    (["--preset", "full"], {"USE_ICU": "maybe"}, "must be 0 or 1"),
    ([], {"USE_ICU": "0", "SQLITE_ENABLE_ICUEX": "1"}, "ICUex requires"),
    ([], {"SQLITE_EXTRA": "0", "SQLITE_ENABLE_REGEXPMATCHES": "1"}, "RegexpMatches requires"),
])
def test_invalid_configuration_precedes_download(tmp_path, arguments, settings, reason):
    root = tmp_path / "out"
    env = dict(os.environ, OUT_DIR=str(root), **settings)
    result = subprocess.run([BASE / "sqlite_build.sh", *arguments], env=env, capture_output=True, text=True)
    assert result.returncode and reason in result.stderr
    assert not (root / "cache").exists()


def test_clean_preserves_unmanaged_directory(tmp_path):
    valuable = tmp_path / "build"
    valuable.mkdir()
    result = subprocess.run([BASE / "sqlite_build.sh", "clean"], env=dict(os.environ, OUT_DIR=str(tmp_path)),
                            capture_output=True, text=True)
    assert result.returncode and valuable.is_dir()
