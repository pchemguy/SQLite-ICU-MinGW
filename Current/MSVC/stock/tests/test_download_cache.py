"""Windows integration tests for the stock cache; no Internet, MSVC or Conda required."""

import io
import os
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import tarfile
from threading import Thread
import zipfile

import pytest


pytestmark = pytest.mark.skipif(os.name != "nt", reason="executes Windows batch files")
STOCK = Path(__file__).resolve().parents[1]
MEMBER = "sqlite/Makefile.msc"


def archive(member=MEMBER):
    data = io.BytesIO()
    with zipfile.ZipFile(data, "w") as z:
        z.writestr(member, "test")
    return data.getvalue()


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


def download(target, url, member=MEMBER):
    return cmd(
        '"%TEST_HELPER%" "SQLite" "%TEST_TARGET%" "%TEST_URL%" "%TEST_MEMBER%"',
        target.parent, TEST_HELPER=str(STOCK / "download_file.bat"),
        TEST_TARGET=str(target), TEST_URL=url, TEST_MEMBER=member,
    )


@pytest.mark.parametrize("media", [None, "application/octet-stream"])
def test_get_preserves_arguments_and_warm_hit_makes_no_request(tmp_path, media):
    body = archive()
    target = tmp_path / "cache & build !.zip"
    with endpoint(body, media) as (base, seen):
        query = "/file?a=one%20two&b=three%2Ffour!five"
        # Match the production callers' second-pass expansion at the CALL boundary.
        wrapper = tmp_path / "outer.bat"
        wrapper.write_bytes(
            b'@setlocal DisableDelayedExpansion\r\n'
            b'@call "%%TEST_HELPER%%" "SQLite" "%%TEST_TARGET%%" "%%TEST_URL%%" "%%TEST_MEMBER%%"\r\n'
            b'@exit /b %errorlevel%\r\n'
        )
        result = cmd('"%TEST_WRAPPER%"', tmp_path, TEST_WRAPPER=str(wrapper),
                     TEST_HELPER=str(STOCK / "download_file.bat"), TEST_TARGET=str(target),
                     TEST_URL=base + query, TEST_MEMBER=MEMBER)
        assert result.returncode == 0, (result.stdout, result.stderr)
        result = download(target, base + query)
        assert result.returncode == 0, (result.stdout, result.stderr)
        assert seen == [("GET", query)]
    assert target.read_bytes() == body


def test_redirect_html_is_not_final_content_type(tmp_path):
    target = tmp_path / "sqlite.zip"
    with endpoint(archive()) as (base, seen):
        assert download(target, base + "/redirect").returncode == 0
        assert seen == [("GET", "/redirect"), ("GET", "/file")]


@pytest.mark.parametrize(("body", "media", "short"), [
    (archive(), "Text/HTML; charset=utf-8", False),
    (b"not an archive", None, False),
    (archive("other/Makefile.msc"), "application/zip", False),
    (b"partial", "application/zip", True),
])
def test_failure_cannot_publish_or_prevent_retry(tmp_path, body, media, short):
    target = tmp_path / "sqlite.zip"
    with endpoint(body, media, short) as (base, _):
        assert download(target, base + "/file").returncode != 0
    assert not target.exists()
    assert not Path(str(target) + ".part").exists()
    with endpoint(archive()) as (base, _):
        assert download(target, base + "/file").returncode == 0


def test_suspect_legacy_cache_fails_without_network_or_overwrite(tmp_path):
    target = tmp_path / "sqlite.zip"
    target.write_bytes(b"legacy partial")
    with endpoint(archive()) as (base, seen):
        assert download(target, base + "/file").returncode != 0
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


def test_zlib_cache_hit_precedes_latest_resolution(tmp_path):
    # Call the real label in isolation; neither helper downloads nor NMake may run.
    with tarfile.open(tmp_path / "zlib.tar.gz", "w:gz") as z:
        z.addfile(tarfile.TarInfo("zlib-1.4/win32/Makefile.msc"))
    driver = tmp_path / "stage.bat"
    driver.write_bytes(
        b"@echo off\r\ncall :ZLIB_DOWNLOAD\r\nexit /b %errorlevel%\r\n"
        + (STOCK / "sqlite_msbuild.bat").read_bytes()
    )
    result = cmd('"%TEST_DRIVER%"', tmp_path, TEST_DRIVER=str(driver),
                 CACHEDIR=str(tmp_path), TAR=os.path.join(os.environ["SystemRoot"], "System32", "tar.exe"),
                 PATH=str(tmp_path))
    assert result.returncode == 0, (result.stdout, result.stderr)
