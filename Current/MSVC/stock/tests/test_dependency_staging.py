"""Offline Windows integration tests for the stock dependency stages."""

import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import zipfile

import pytest


STOCK = Path(__file__).resolve().parents[1]
pytestmark = pytest.mark.skipif(os.name != "nt", reason="executes Windows CMD and tar")


@pytest.fixture
def stage(tmp_path):
    shutil.copyfile(STOCK / "extract_archive.bat", tmp_path / "extract_archive.bat")
    driver = tmp_path / "stage.bat"
    driver.write_bytes(b"@echo off\r\n@setlocal EnableDelayedExpansion\r\n"
                       b"call :%1\r\nexit /b %errorlevel%\r\n"
                       + (STOCK / "sqlite_msbuild.bat").read_bytes())

    def run(label, **extra):
        env = os.environ.copy()
        env.update(NO_COLOR="1", OUT=str(tmp_path), CACHEDIR=str(tmp_path),
                   THIRDDIR=str(tmp_path), ZLIBDIR=str(tmp_path / "zlib"),
                   ICUDIR=str(tmp_path / "icu"), ARCH="64",
                   ICUINCDIR=str(tmp_path / "icu/include"), ICULIBDIR=str(tmp_path / "icu/lib64"),
                   ICUBINDIR=str(tmp_path / "icu/bin64"), SQLITEDIR=str(tmp_path / "sqlite"),
                   SQLITE_MAKEFILE=str(tmp_path / "sqlite/Makefile.msc"), **extra)
        return subprocess.run([os.environ["COMSPEC"], "/d", "/c", driver.name, label],
                              cwd=tmp_path, env=env, capture_output=True, text=True, timeout=20)
    return run


def test_extract_relative_paths_without_changing_cwd(tmp_path):
    with zipfile.ZipFile(tmp_path / "input.zip", "w") as z:
        z.writestr("inside", "ok")
    (tmp_path / "some dir").mkdir()
    driver = tmp_path / "check.bat"
    driver.write_text(f'@echo off\nset "BEFORE=%CD%"\nset "TAR="\ncall "{STOCK / "extract_archive.bat"}" '
                      '"test" "some dir\\inside" "input.zip" "some dir" || exit /b 1\n'
                      'if not "%CD%"=="%BEFORE%" exit /b 2\n')
    result = subprocess.run([os.environ["COMSPEC"], "/d", "/c", driver.name], cwd=tmp_path)
    assert result.returncode == 0
    assert (tmp_path / "some dir/inside").read_text() == "ok"
    assert not (tmp_path / "inside").exists()


def test_tar_rejects_a_file_as_destination(tmp_path):
    with zipfile.ZipFile(tmp_path / "input.zip", "w") as z:
        z.writestr("must-not-land-here", "data")
    (tmp_path / "not a dir").touch()
    command = f'""{STOCK / "extract_archive.bat"}" test "not a dir\\must-not-land-here" input.zip "not a dir""'
    result = subprocess.run(f'"{os.environ["COMSPEC"]}" /d /s /c {command}', cwd=tmp_path)
    assert result.returncode != 0
    assert not (tmp_path / "must-not-land-here").exists()


def test_sqlite_reuses_extracted_makefile(stage, tmp_path):
    sqlite = tmp_path / "sqlite"
    with zipfile.ZipFile(tmp_path / "sqlite.zip", "w") as z:
        z.writestr("sqlite/Makefile.msc", "original")
    result = stage("SQLITE_EXTRACT")
    assert result.returncode == 0, result.stdout
    assert list(sqlite.iterdir()) == [sqlite / "Makefile.msc"]
    (sqlite / "Makefile.msc").write_text("keep")
    assert stage("SQLITE_EXTRACT").returncode == 0
    assert (sqlite / "Makefile.msc").read_text() == "keep"


@pytest.mark.parametrize("names, valid", [
    (["zlib-1.3.1"], True), (["zlib-latest"], False), (["zlib-1.3", "zlib-1.4"], False),
])
def test_zlib_publishes_one_versioned_root(stage, tmp_path, names, valid):
    with tarfile.open(tmp_path / "zlib.tar.gz", "w:gz") as tar:
        for name in names:
            tar.addfile(tarfile.TarInfo(f"{name}/win32/Makefile.msc"))
    final = tmp_path / "zlib"
    result = stage("ZLIB_EXTRACT")
    assert (result.returncode == 0) == valid, result.stdout
    assert final.exists() == valid
    if valid:
        assert list(final.iterdir()) == [final / "win32"]
        (tmp_path / "zlib.tar.gz").unlink()
        assert stage("ZLIB_EXTRACT").returncode == 0
        (final / "win32/Makefile.msc").unlink()
        assert stage("ZLIB_EXTRACT").returncode != 0


def test_icu_publishes_and_reuses_one_set(stage, tmp_path):
    prefix = tmp_path / "Conda env"
    libs = prefix / "Library"
    headers = ["utypes.h", "ucol.h", "ustring.h", "uregex.h"]
    paths = ([f"include/unicode/{h}" for h in headers]
             + [f"lib/{n}.lib" for n in ("icudt", "icuuc", "icuin", "icuio")]
             + [f"bin/{n}" for n in ("icuinfo.exe", "icudt78.dll", "icuuc78.dll", "icuin78.dll",
                                        "icuuc.dll", "icutest78.dll")])
    for path in paths:
        item = libs / path
        item.parent.mkdir(parents=True, exist_ok=True)
        item.write_bytes(b"original")
    (prefix / "python.exe").touch()
    final = tmp_path / "icu"
    def run():
        return stage("ICU_CONDA", CONDA_PREFIX=str(prefix))

    result = run()
    assert result.returncode == 0, result.stdout
    assert not (final / "bin64/icuuc.dll").exists()
    assert not (final / "bin64/icutest78.dll").exists()
    (libs / "bin/icuuc78.dll").write_bytes(b"new")
    assert run().returncode == 0
    assert (final / "bin64/icuuc78.dll").read_bytes() == b"original"
    (final / "lib64/icuuc.lib").unlink()
    assert run().returncode != 0
    assert not (final / "lib64/icuuc.lib").exists()


def test_icu_missing_partner_never_publishes(stage, tmp_path):
    prefix = tmp_path / "prefix"
    for name in ("python.exe", "Library/bin/icuinfo.exe", "Library/bin/icuuc77.dll",
                 "Library/bin/icudt78.dll", "Library/bin/icuin77.dll", "Library/lib/icudt.lib",
                 "Library/lib/icuuc.lib", "Library/lib/icuin.lib", "Library/include/unicode/utypes.h",
                 "Library/include/unicode/ucol.h", "Library/include/unicode/uregex.h", "Library/include/unicode/ustring.h"):
        item = prefix / name
        item.parent.mkdir(parents=True, exist_ok=True)
        item.write_bytes(b"fixture")
    result = stage("ICU_CONDA", CONDA_PREFIX=str(prefix))
    assert result.returncode != 0
    assert "icudt77.dll" in result.stdout
    assert not (tmp_path / "icu").exists()


@pytest.fixture(scope="module")
def release_curl(tmp_path_factory):
    """Stand in for GitHub's redirect and cURL's exit code without network access."""
    cc = shutil.which("cl.exe")
    if not cc:
        pytest.skip("requires the MSVC developer prompt to build the cURL stub")
    directory = tmp_path_factory.mktemp("release-curl")
    source = directory / "curl.c"
    source.write_text('#include <stdio.h>\n#include <stdlib.h>\n'
                      'int main(void) { puts(getenv("EFFECTIVE_URL")); return atoi(getenv("CURL_RC")); }\n')
    subprocess.run([cc, "/nologo", "curl.c"], cwd=directory, check=True)
    return directory


@pytest.mark.parametrize("url, rc, valid", [
    ("https://github.com/madler/zlib/releases/tag/v1.4", 0, True),
    ("https://github.com/madler/zlib/releases/tag/v1.3.1", 0, True),
    ("https://github.com/madler/zlib/releases/tag/v1.4", 22, False),
    ("https://github.com/other/zlib/releases/tag/v1.4", 0, False),
    ("https://github.com/madler/zlib/releases/tag/v1..4", 0, False),
    ("https://github.com/madler/zlib/releases/latest", 0, False),
])
def test_release_lookup(stage, tmp_path, release_curl, url, rc, valid):
    (tmp_path / "download_file.bat").write_text('@>"asset.txt" echo %~3\n@exit /b 0\n')
    result = stage("ZLIB_DOWNLOAD", EFFECTIVE_URL=url, CURL_RC=str(rc), ZLIB_VERSION="v9.9",
                   PATH=str(release_curl) + os.pathsep + os.environ["PATH"])
    assert (result.returncode == 0) == valid, result.stdout
    asset = tmp_path / "asset.txt"
    assert asset.exists() == valid
    if valid:
        version = url.rsplit("/v", 1)[1]
        assert asset.read_text().strip() == f"https://github.com/madler/zlib/releases/download/v{version}/zlib-{version}.tar.gz"
