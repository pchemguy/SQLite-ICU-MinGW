"""Windows integration tests for the stock cache; no Internet, MSVC or Conda required."""

import os
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
from threading import Thread

import pytest


pytestmark = pytest.mark.skipif(os.name != "nt", reason="executes Windows batch files")
STOCK = Path(__file__).resolve().parents[1]


@contextmanager
def endpoint(body, media="application/octet-stream", short=False):
    requests = []

    class Handler(BaseHTTPRequestHandler):
        def do_HEAD(self):
            requests.append(("HEAD", self.path))
            self.send_error(405)

        def do_GET(self):
            requests.append(("GET", self.path))
            if self.path == "/redirect":
                self.send_response(302)
                self.send_header("Location", "/file")
                self.send_header("Content-Type", "text/html")
            else:
                self.send_response(200)
                if media is not None:
                    self.send_header("Content-Type", media)
                self.send_header("Content-Length", str(len(body) + int(short)))
            self.end_headers()
            if self.path != "/redirect":
                self.wfile.write(body)

        def log_message(self, *args):
            pass

    with ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
        thread = Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            yield f"http://127.0.0.1:{server.server_port}", requests
        finally:
            server.shutdown()
            thread.join()


def cmd(command, directory, **extra):
    env = dict(os.environ, NO_COLOR="1", NO_PROXY="127.0.0.1", **extra)
    return subprocess.run(
        f'cmd.exe /d /v:off /s /c "{command}"', cwd=directory, env=env,
        capture_output=True, text=True, timeout=45,
    )


def download(target, url):
    return cmd(
        '"%TEST_HELPER%" "SQLite" "%TEST_TARGET%" "%TEST_URL%"',
        target.parent, TEST_HELPER=str(STOCK / "download_file.bat"),
        TEST_TARGET=str(target), TEST_URL=url,
    )


@pytest.mark.parametrize("media", [None, "application/octet-stream"])
def test_get_preserves_arguments_and_warm_hit_makes_no_request(tmp_path, media):
    body = b"opaque payload"
    target = tmp_path / "cache & build !.zip"
    with endpoint(body, media) as (base, seen):
        query = "/file?a=one%20two&b=three%2Ffour!five"
        # Keep percent escapes literal when this test passes its URL through CALL.
        wrapper = tmp_path / "outer.bat"
        wrapper.write_bytes(
            b'@setlocal DisableDelayedExpansion\r\n'
            b'@call "%%TEST_HELPER%%" "SQLite" "%%TEST_TARGET%%" "%%TEST_URL%%"\r\n'
            b'@exit /b %errorlevel%\r\n'
        )
        result = cmd('"%TEST_WRAPPER%"', tmp_path, TEST_WRAPPER=str(wrapper),
                     TEST_HELPER=str(STOCK / "download_file.bat"), TEST_TARGET=str(target),
                     TEST_URL=base + query)
        assert result.returncode == 0, (result.stdout, result.stderr)
        result = download(target, base + query)
        assert result.returncode == 0, (result.stdout, result.stderr)
        assert seen == [("GET", query)]
    assert target.read_bytes() == body


def test_redirect_html_is_not_final_content_type(tmp_path):
    target = tmp_path / "sqlite.zip"
    with endpoint(b"payload") as (base, seen):
        assert download(target, base + "/redirect").returncode == 0
        assert seen == [("GET", "/redirect"), ("GET", "/file")]


@pytest.mark.parametrize(("body", "media", "short"), [
    (b"unexpected content", "Text/HTML; charset=utf-8", False),
    (b"partial", "application/zip", True),
])
def test_failure_cannot_publish_or_prevent_retry(tmp_path, body, media, short):
    target = tmp_path / "sqlite.zip"
    with endpoint(body, media, short) as (base, _):
        assert download(target, base + "/file").returncode != 0
    assert not target.exists()
    assert not Path(str(target) + ".part").exists()
    with endpoint(b"retry") as (base, _):
        assert download(target, base + "/file").returncode == 0


def test_existing_target_is_reused_without_network_or_overwrite(tmp_path):
    target = tmp_path / "sqlite.zip"
    target.write_bytes(b"legacy partial")
    with endpoint(b"replacement") as (base, seen):
        assert download(target, base + "/file").returncode == 0
        assert not seen
    assert target.read_bytes() == b"legacy partial"


def test_three_argument_download_replaces_leftover_part(tmp_path):
    target = tmp_path / "sample.log"
    part = Path(str(target) + ".part")
    part.write_bytes(b"leftover")
    with endpoint(b"new", "text/plain") as (base, seen):
        result = cmd('"%TEST_HELPER%" "sample" "%TEST_TARGET%" "%TEST_URL%"', tmp_path,
                     TEST_HELPER=str(STOCK / "download_file.bat"),
                     TEST_TARGET=str(target), TEST_URL=base + "/file")
        assert result.returncode == 0, (result.stdout, result.stderr)
        assert seen == [("GET", "/file")]
    assert target.read_bytes() == b"new" and not part.exists()


def test_missing_url_does_not_open_logs(tmp_path):
    result = cmd('"%TEST_HELPER%" "sample" "test.zip"', tmp_path,
                 TEST_HELPER=str(STOCK / "download_file.bat"))
    assert result.returncode != 0
    assert not list(tmp_path.iterdir())


@pytest.mark.parametrize(("name", "stage"), [("sqlite.zip", "SQLITE_DOWNLOAD"), ("zlib.tar.gz", "ZLIB_DOWNLOAD")])
def test_cached_target_needs_neither_curl_nor_tar(tmp_path, name, stage):
    (tmp_path / name).write_bytes(b"opaque cache entry")
    (tmp_path / "download_file.bat").write_bytes((STOCK / "download_file.bat").read_bytes())
    driver = tmp_path / "stage.bat"
    driver.write_bytes(
        f"@echo off\r\ncall :{stage}\r\nexit /b %errorlevel%\r\n".encode("ascii")
        + (STOCK / "sqlite_msbuild.bat").read_bytes()
    )
    result = cmd('"%TEST_DRIVER%"', tmp_path, TEST_DRIVER=str(driver),
                 CACHEDIR=str(tmp_path), TAR=str(tmp_path / "absent-tar.exe"), PATH=str(tmp_path))
    assert result.returncode == 0, (result.stdout, result.stderr)
