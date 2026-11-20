"""Stock MSVC preflight. Run with pytest in a Windows developer prompt for PE checks."""

import os
from pathlib import Path
import shutil
import struct
import subprocess

import pytest


STOCK = Path(__file__).resolve().parents[1]
TOOLS = ("cl.exe", "nmake.exe", "dumpbin.exe", "lib.exe", "curl.exe")


def test_one_preflight_before_icu_paths():
    main = (STOCK / "sqlite_msbuild.bat").read_text()
    check = 'call "%~dp0msbuild_check.bat"'
    assert main.count(check) == 1
    assert main.index("call :CORE_ENV") < main.index(check) < main.index("call :ICU_OPTIONS")


@pytest.fixture
def preflight(tmp_path):
    if os.name != "nt":
        pytest.skip("executes Windows batch files")
    sys32 = Path(os.environ["SystemRoot"]) / "System32"
    for name in ("where.exe", "findstr.exe"):
        shutil.copyfile(sys32 / name, tmp_path / name)
    for name in TOOLS:
        (tmp_path / name).touch()  # WHERE probes only, except in the real DUMPBIN test.
    windows = tmp_path / "Windows"
    (windows / "System32").mkdir(parents=True)
    (windows / "System32" / "tar.exe").touch()

    def run(**settings):
        env = os.environ.copy()
        env.update(PATH=str(tmp_path), WINDIR=str(windows), VCINSTALLDIR="fixture",
                   VISUALSTUDIOVERSION="17.0", VSCMD_ARG_TGT_ARCH="x64", USE_ICU="0",
                   CONDA_PREFIX="", NO_COLOR="1")
        env.update(settings)
        return subprocess.run(f'"{env["COMSPEC"]}" /d /c ""{STOCK / "msbuild_check.bat"}""',
                              env=env, cwd=tmp_path, capture_output=True, text=True, timeout=20)

    return run


@pytest.mark.parametrize("arch", ["X86", "x64", "", "arm64"])
def test_target_and_optional_tcl(preflight, arch):
    result = preflight(VSCMD_ARG_TGT_ARCH=arch)
    assert (result.returncode == 0) == (arch.lower() in {"x86", "x64"}), result.stdout
    assert "tclsh.exe was not found" in result.stdout
    if result.returncode:
        assert "VSCMD_ARG_TGT_ARCH" in result.stdout


@pytest.mark.parametrize("missing", ["curl.exe", "lib.exe", "dumpbin.exe", "Windows/System32/tar.exe"])
def test_missing_required_tool(preflight, tmp_path, missing):
    (tmp_path / missing).unlink()
    result = preflight()
    assert result.returncode != 0
    assert Path(missing).name in result.stdout


def test_missing_vcinstalldir(preflight):
    result = preflight(VCINSTALLDIR="")
    assert result.returncode != 0
    assert "%VCINSTALLDIR% is not set" in result.stdout


def test_icu_machine(preflight, tmp_path):
    dumpbin = shutil.which("dumpbin.exe")
    if not dumpbin:
        pytest.skip("requires MSVC DUMPBIN on PATH")
    (tmp_path / "dumpbin.exe").unlink()
    prefix = tmp_path / "Conda env"
    dll = prefix / "Library" / "bin" / "icuuc78.dll"
    dll.parent.mkdir(parents=True)
    options = dict(USE_ICU="1", CONDA_PREFIX=str(prefix),
                   PATH=os.pathsep.join([str(tmp_path), str(Path(dumpbin).parent), os.environ["PATH"]]))
    assert preflight(**options).returncode != 0  # No versioned common DLL.
    shutil.copyfile(Path(os.environ["SystemRoot"]) / "System32" / "kernel32.dll", dll)
    image = dll.read_bytes()
    pe = struct.unpack_from("<I", image, 60)[0]
    machine = struct.unpack_from("<H", image, pe + 4)[0]
    if machine not in (0x14C, 0x8664):
        pytest.skip("fixture DLL is neither x86 nor x64")
    for arch, expected in [("x86", 0x14C), ("x64", 0x8664)]:
        result = preflight(VSCMD_ARG_TGT_ARCH=arch, **options)
        assert (result.returncode == 0) == (machine == expected), result.stdout
        assert str(dll) in result.stdout and arch in result.stdout
        assert f"{machine:X}" in result.stdout.upper()
    dll.write_bytes(b"not a PE image")
    assert preflight(**options).returncode != 0
