import os
from pathlib import Path
import shlex
import shutil
import subprocess

import pytest


HARNESS = Path(__file__).resolve().parents[1] / "sqlite_build.sh"
CLIENT = Path(__file__).with_name("client.c")
SWITCHES = ("USE_ICU", "SQLITE_EXTRA", "USE_EXTRAS", "SQLITE_ENABLE_ICUEX",
            "SQLITE_ENABLE_PBLOB", "SQLITE_ENABLE_REGEXPMATCHES")

# Each stock source has a distinctive registration on a library connection.
# regexpi distinguishes ext/misc/regexp.c from upstream ICU's regexp().
STOCK = {
    "function": {"compress", "decimal", "noop", "regexpi", "remember", "rot13",
                 "sha1", "sha3", "sqlar_compress", "uuid"},
    "module": {"csv", "fuzzer", "prefixes", "generate_series"},
    "collation": {"uint"},
}
PROJECT = {
    "icuex": {("str_casefold", 1), ("str_normalize", 2)},
    "pblob": {("pblob_pack", 1), ("pblob_pack", 2), ("pblob_unpack", 1)},
    "regexpmatches": {("regexp_matches", 2), ("regexpi_matches", 2)},
}
ALL_PROJECT = frozenset(PROJECT)


def output(args, env=None):
    return subprocess.check_output(args, env=env, text=True).strip()


def sql(command, query):
    return output([*command, query])


def clients(prefix, tmp_path):
    env = dict(os.environ, PKG_CONFIG_PATH=str(prefix / "lib/pkgconfig"))
    flags = shlex.split(output(["pkg-config", "--cflags", "sqlite3"], env))
    cc = os.environ.get("CC", "gcc")
    shared = tmp_path / "shared-client"
    static = tmp_path / "static-client"
    local_lib = prefix / "lib"
    for target, mode in ((shared, []), (static, ["--static"])):
        libs = shlex.split(output(["pkg-config", *mode, "--libs", "sqlite3"], env))
        if target == static:
            libs[libs.index("-lsqlite3")] = str(local_lib / "libsqlite3.a")
        else:
            libs.append(f"-Wl,-rpath,{local_lib}")
        subprocess.run([cc, *flags, CLIENT, "-o", target, *libs], check=True)
    loader_env = dict(os.environ)
    loader_env.pop("LD_LIBRARY_PATH", None)
    resolved = output(["ldd", shared], loader_env)
    sqlite_entry = next(line for line in resolved.splitlines() if "libsqlite3.so.0 =>" in line)
    loaded = sqlite_entry.split("=>", 1)[1].split(" (", 1)[0].strip()
    assert Path(loaded).resolve() == (local_lib / "libsqlite3.so.0").resolve()
    assert "libsqlite3.so" not in output(["readelf", "-d", static])
    return [[shared], [static]]


def check_connection(command, icu, stock, project, shell=False):
    functions = set(sql(command, "SELECT DISTINCT name FROM pragma_function_list").splitlines())
    modules = set(sql(command, "SELECT name FROM pragma_module_list").splitlines())
    collations = set(sql(command, "SELECT name FROM pragma_collation_list").splitlines())
    if not shell or stock:
        for kind, actual in (("function", functions), ("module", modules), ("collation", collations)):
            assert STOCK[kind] & actual == (STOCK[kind] if stock else set())
    assert ("icu_load_collation" in functions) == icu
    if icu:
        assert sql(command, "SELECT hex(lower('I','tr_TR'))") == "C4B1"
    assert {"UTF_CI", "UTF_CI_AI"} & collations == ({"UTF_CI", "UTF_CI_AI"} if "icuex" in project else set())

    wanted = set().union(*(PROJECT[name] for name in project))
    names = {name for pairs in PROJECT.values() for name, _ in pairs}
    names_sql = ",".join(f"'{name}'" for name in sorted(names))
    rows = sql(command, f"SELECT name,narg,builtin,type,enc,flags FROM pragma_function_list WHERE name IN ({names_sql})")
    assert set(rows.splitlines()) == {f"{name}|{arity}|0|s|utf8|2099200" for name, arity in wanted}
    if "icuex" in project:
        assert sql(command, "SELECT str_casefold('Stra\u00dfe'), str_normalize('\u00c4','NFKD_CF_STRIP'), '\u00e9'='e' COLLATE UTF_CI_AI") == "strasse|a|1"
    if "pblob" in project:
        assert sql(command, """SELECT typeof(pblob_pack('[1,2]')),
            json_extract(pblob_unpack(pblob_pack('[1,2]','<f4')),'$[1]')=2""") == "blob|1"
    if "regexpmatches" in project:
        assert sql(command, "SELECT regexp_matches('[0-9]+','a12b3'),regexpi_matches('a+','aA b a')") == '["12","3"]|["aA","a"]'
    if stock:
        assert sql(command, "SELECT hex(uncompress(compress(x'cafe'))), rot13('alpha'), sum(value) FROM generate_series(1,3)") == "CAFE|nycun|6"
    if not shell:
        options = set(sql(command, "PRAGMA compile_options").splitlines())
        assert {"ENABLE_SESSION", "ENABLE_PREUPDATE_HOOK", "ENABLE_RBU", "ENABLE_API_ARMOR",
                "ENABLE_FTS5", "ENABLE_STAT4", "DQS=0", "MAX_ATTACHED=100", "MAX_EXPR_DEPTH=100"} <= options
        assert sql(command, "PRAGMA foreign_keys") == "1"


@pytest.mark.parametrize(("preset", "overrides", "icu", "stock", "project"), [
    pytest.param("bare", {}, False, False, set(), id="bare"),
    pytest.param("bare-icu", {}, True, False, set(), id="bare-icu"),
    pytest.param("bare-icu-ext", {}, True, True, set(), id="bare-icu-ext"),
    pytest.param("full", {}, True, True, ALL_PROJECT, id="full"),
    pytest.param("full", {"SQLITE_ENABLE_ICUEX": "0"}, True, True, ALL_PROJECT - {"icuex"}, id="no-icuex"),
    pytest.param("full", {"SQLITE_ENABLE_PBLOB": "0"}, True, True, ALL_PROJECT - {"pblob"}, id="no-pblob"),
    pytest.param("full", {"SQLITE_ENABLE_REGEXPMATCHES": "0"}, True, True, ALL_PROJECT - {"regexpmatches"}, id="no-regexpmatches"),
    pytest.param("full", {"SQLITE_EXTRA": "0"}, True, False, {"icuex", "pblob"}, id="project-only"),
])
def test_distribution(build_root, tmp_path, preset, overrides, icu, stock, project):
    env = {key: value for key, value in os.environ.items() if key not in SWITCHES}
    env.update(overrides, OUT_DIR=str(build_root))
    subprocess.run([HARNESS, "--preset", preset], cwd=tmp_path, env=env, check=True)

    # Copy only the redistributable prefix and validate its symlinks and .pc.
    prefix = tmp_path / "relocated"
    shutil.copytree(build_root / "package", prefix, symlinks=True)
    assert {f.name for f in (prefix / "bin").iterdir()} == {"sqlite3"}
    assert {f.name for f in (prefix / "include").iterdir()} >= {"sqlite3.h", "sqlite3ext.h", "sqlite3session.h"}
    library = prefix / "lib/libsqlite3.so"
    assert library.resolve() == (prefix / "lib/libsqlite3.so.0").resolve()
    assert "Library soname: [libsqlite3.so.0]" in output(["readelf", "-d", library])
    assert not list((prefix / "lib").glob("libicu*")) and not list((prefix / "lib").glob("libz.*"))

    check_connection([prefix / "bin/sqlite3", "-batch", "-init", "/dev/null", ":memory:"], icu, stock, project, shell=True)
    for command in clients(prefix, tmp_path):
        check_connection(command, icu, stock, project)
    if preset == "full" and not overrides:
        verify_cached_rebuild(build_root, tmp_path, env)


def verify_cached_rebuild(root, tmp_path, env):
    """Exercise a warm offline build and a failure before publication."""
    commands = tmp_path / "commands"
    commands.mkdir()
    curl = commands / "curl"
    curl.write_text('#!/bin/sh\necho "unexpected network request" >&2\nexit 89\n')
    curl.chmod(0o755)
    env = dict(env, PATH=f"{commands}{os.pathsep}{env['PATH']}")
    manifest = root / "build/build-inputs.txt"
    ready = root / "build/tsrc/.extensions-ready"
    prepared = (manifest.stat().st_mtime_ns, ready.stat().st_mtime_ns)
    subprocess.run([HARNESS], env=env, cwd=tmp_path, check=True)
    assert (manifest.stat().st_mtime_ns, ready.stat().st_mtime_ns) == prepared
    published = (root / "package").resolve()
    install = commands / "install"
    env["REAL_INSTALL"] = shutil.which("install", path=env["PATH"])
    install.write_text('#!/bin/sh\nfor arg do case "$arg" in */libsqlite3.a) exit 73;; esac; done\nexec "$REAL_INSTALL" "$@"\n')
    install.chmod(0o755)
    failure = subprocess.run([HARNESS], env=env, cwd=tmp_path)
    assert failure.returncode == 73
    assert (root / "package").resolve() == published
    assert not list(root.glob(".work.*"))
    assert sql([root / "bin/sqlite3", "-batch", "-init", "/dev/null", ":memory:"], "SELECT str_casefold('ABC')") == "abc"
