# Building SQLite with GCC on Linux

`./sqlite_build.sh` builds the SQLite CLI and shared and static libraries on Linux. `./sqlite_build_conda.sh` installs the selected build into a local Conda Python environment. The `./sqlite_ext_*.sh` hooks register project extensions, `./tool/` contains build helpers and the Conda bootstrap, and `./tests/` verifies the builds.

The default build includes upstream ICU support, 15 stock SQLite modules, and the ICUex, PBLOB and RegexpMatches project extensions. Applications get the selected extensions on each new SQLite connection.

## Build

The build requires Bash, GCC, GNU Make, binutils, `flock` and standard GNU utilities. Fetching and extracting sources uses `curl` and `unzip`. The harness uses `tclsh` if available or builds SQLite's bundled Jim interpreter. The ordinary build runs without Python.

```bash
./sqlite_build.sh
./out/bin/sqlite3 :memory: "SELECT str_casefold('ABC'), typeof(pblob_pack('[1,2]')), regexp_matches('[0-9]+','a12b3');"
```

The full build returns `abc|blob|["12","3"]`. The script resolves its paths from its own directory and can be invoked from another working directory.

### Use the build from Conda Python

Run the wrapper with the SQLite preset you want. The default is `full`, which includes ICUex, PBLOB and RegexpMatches. The bundled Conda bootstrap supports glibc-based x86-64 and AArch64 Linux. Choose a writable output path without whitespace. [Presets and switches](#presets-and-switches)

```bash
./sqlite_build_conda.sh --preset full
```

The wrapper checks for an executable `./out/conda/bin/python`. On first setup the bootstrap downloads Micromamba, creates the environment from `./tool/conda_env/Anaconda_bootstrap.yml`, installs the project packages from `./tool/conda_env/Anaconda.yml`, and generates `./out/conda_activate.sh`. Later runs reuse that environment. [Bootstrap files](./tool/conda_env/)

Each run removes `./out/bin` and `./out/build`, reuses the cached sources, and passes the preset to `./sqlite_build.sh`. It then atomically replaces the file behind `./out/conda/lib/libsqlite3.so.0`, preserving Conda's library symlinks and cached package.

The wrapper starts `./out/conda/bin/python` in isolated mode, opens a SQLite connection, and uses the process's memory mappings to identify the loaded library. It compares that file byte for byte with `./out/lib/libsqlite3.so.0`. On success it prints the interpreter, the loaded library path, and SQLite's runtime version and source ID. The library filename can still carry Conda's original version. If verification fails, the wrapper restores the previous library.

#### Run Python and check the extensions

For scripts and tests, invoke the environment's Python directly. This query exercises all three project extensions on one connection after a `full` build.

```bash
./out/conda/bin/python -I - <<'PY'
import sqlite3

with sqlite3.connect(":memory:") as db:
    row = db.execute("""
        SELECT str_casefold('ABC'),
               typeof(pblob_pack('[1,2]')),
               regexp_matches('[0-9]+', 'a12b3')
    """).fetchone()
    print(row)
PY
```

The expected result is `('abc', 'blob', '["12","3"]')`.

For interactive work, source the generated launcher in each new Bash shell. This prints the active interpreter and its SQLite version.

```bash
source ./out/conda_activate.sh
python -c 'import sqlite3, sys; print(sys.executable, sqlite3.sqlite_version)'
conda deactivate
```

#### Switch presets or keep separate environments

Rerun the wrapper with a different `--preset` to replace SQLite in the same environment. Start a fresh Python process to load the replacement. If a Conda package update reinstalls its own `libsqlite`, rerun the wrapper with your chosen preset.

To keep a separate `bare` environment, set `OUT_DIR=./out-bare`. Use its interpreter directly or source `./out-bare/conda_activate.sh`.

```bash
OUT_DIR=./out-bare ./sqlite_build_conda.sh --preset bare
./out-bare/conda/bin/python -c 'import sqlite3; print(sqlite3.sqlite_version)'
```

### Presets and switches

| `--preset` | Upstream ICU | Stock modules | Project extensions | Required system development packages |
|---|---|---|---|---|
| `bare` | Off | Off | Off | None |
| `bare-icu` | On | Off | Off | ICU |
| `bare-icu-ext` | On | All 15 | Off | ICU, zlib |
| `full` (default) | On | All 15 | ICUex, PBLOB, RegexpMatches | ICU, zlib |

`./sqlite_build.sh --check-preset NAME` checks a preset name without starting a build. Environment switches accept `0` or `1` and override the preset.

| Variable | Effect |
|---|---|
| `USE_ICU` | Enable SQLite's upstream ICU functions and ICU collations. |
| `SQLITE_EXTRA` | Build the 15 stock modules. The compression and SQL archive modules require zlib. |
| `USE_EXTRAS` | Enable the project hooks. Setting this to `0` skips all project downloads. |
| `SQLITE_ENABLE_ICUEX` | Select ICUex. Defaults to `USE_ICU` and requires ICU. |
| `SQLITE_ENABLE_PBLOB` | Select PBLOB. Defaults to `1` when project hooks run and fetches the FP16 headers. |
| `SQLITE_ENABLE_REGEXPMATCHES` | Select RegexpMatches. Defaults to `SQLITE_EXTRA` and requires the stock regular expression module. |

```bash
OUT_DIR=./out-bare ./sqlite_build.sh --preset bare
SQLITE_ENABLE_PBLOB=0 ./sqlite_build.sh --preset full
SQLITE_EXTRA=0 ./sqlite_build.sh --preset full
```

The last command builds ICUex and PBLOB without the stock set. SQLite JSON is required by PBLOB and RegexpMatches. `CC` selects the compiler executable (default `gcc`), `CFLAGS` defaults to `-O2`, and `JOBS` sets GNU Make parallelism. `CPPFLAGS` and `LDFLAGS` are passed through to configure. SQLite's configure requires a space-free source and build path. Set `OUT_DIR` to a space-free location when the harness is in a directory with spaces.

### System dependencies

When ICU is selected, the harness probes `icu-i18n` and `icu-uc` with `pkg-config` and passes their flags directly to configure. SQLite and ICUex call both APIs. Specifying them explicitly also works on Fedora, where `icu-io` alone contributes only `-licuio`. When the stock modules are selected, the harness probes `zlib` and checks that configure found its headers and library.

| Package manager | ICU | zlib | Provider of `pkg-config` if missing |
|---|---|---|---|
| APT | `libicu-dev` | `zlib1g-dev` | `pkg-config` |
| DNF | `libicu-devel` | `pkgconfig(zlib)` | `pkgconf-pkg-config` |

A missing requirement triggers installation through APT or DNF, followed by a second probe. Only package installation and the APT index refresh use `sudo` when the caller is an ordinary user. Other distributions can build with the required modules already installed. The `bare` and `bare-icu` presets leave optional zlib support to SQLite's own detection. ICU and zlib runtime libraries are resolved by the system loader.

## Local outputs

`OUT_DIR` defaults to `./out/` beside the driver. The paths below show the default layout.

| Default path | Contents |
|---|---|
| `./out/bin/sqlite3` | Native SQLite CLI |
| `./out/lib/libsqlite3.so`, `./out/lib/libsqlite3.so.0` | Linker and runtime symlinks to `./out/lib/libsqlite3.so.<version>` |
| `./out/lib/libsqlite3.a` | Static SQLite library |
| `./out/include/sqlite3.h`, `./out/include/sqlite3ext.h`, `./out/include/sqlite3session.h` | SQLite public, extension and session headers |
| `./out/lib/pkgconfig/sqlite3.pc` | Relocatable compiler and linker flags, including dependencies for static linking |
| `./out/cache/` | SQLite source ZIP, selected project C files, and the FP16 ZIP for PBLOB |
| `./out/sqlite/` | Extracted SQLite source tree |
| `./out/build/` | Configured build, staged sources in `./out/build/tsrc/`, and generated `./out/build/sqlite3.c` |
| `./out/build/build-inputs.txt` | Source digests, effective flags, compiler and dependency information |

`./out/bin`, `./out/include` and `./out/lib` point into `./out/package/`. The harness stages and verifies the distribution before switching the `./out/package` symlink. To make a copy that preserves the relative library symlinks, run

```bash
mkdir -p ./dist
cp -a ./out/package/. ./dist/
```

For a shared-library consumer, set `PKG_CONFIG_PATH=./out/lib/pkgconfig` and select the local library at runtime. For static linking, use `./out/lib/libsqlite3.a` and retain the private system link flags from `pkg-config --static --libs sqlite3`. The installed CLI embeds the customized amalgamation. The tests exercise the packaged libraries through separate C clients.

## Source preparation and reuse

Start at `main()` to follow the build in execution order. `collect_extensions()` selects the sources, `prepare_target_sources()` stages them for the amalgamation, and `publish_package()` switches the verified prefix into place. [Build driver](./sqlite_build.sh)

The first build caches SQLite's canonical source archive at `./out/cache/sqlite.zip`, fetches the selected project extension sources, and downloads the FP16 headers when PBLOB is enabled. Downloads follow redirects, retry, and enter the cache only after a complete HTTP 200 response with a non-HTML body. Extraction checks the expected source files before publishing the source tree. Later builds reuse the cached inputs. To refresh an upstream source, move its cached file aside and rebuild. [Source helpers](./tool/sources.sh)

After `make .target_source`, the two Tcl helpers patch extension initializers, generate `./out/build/tsrc/misc_ext_init.c` and bundle local headers. The ordered `EXTRA_SRC` list puts the stock regex engine before RegexpMatches, which uses its private definitions. Both PBLOB and RegexpMatches also use SQLite's private JSON code. The PBLOB hook declares `SQLITE_RESULT_SUBTYPE` on the staged `pblob_unpack` registration so the strict upstream CLI can return nested JSON. The cached upstream source stays available for subsequent builds.

The Bash hooks beside the driver run in filename order after the stock modules. A hook can use `project_source REPOSITORY BASENAME MACRO` to fetch a C file and add it to the amalgamation, or `add_source PATH MACRO` for a local file. Preparation callbacks run later, during `prepare_target_sources()`. The PBLOB hook assigns its FP16 archive path when it registers the callback so the callback can read it during staging. The driver rebuilds generated code when effective settings or inputs change and serializes builds using the same output root. [PBLOB hook](./sqlite_ext_pblob.sh)

`./sqlite_build.sh clean` removes the managed source, build and package outputs while retaining `./out/cache/`. Use a separate `OUT_DIR` to keep several presets available side by side.

## Verification

Run the cache and dependency tests and the native build matrix with Python, pytest, `pkg-config`, GCC and binutils available.

```bash
python3 -m pytest -v ./tests
```

The native tests build all four presets, disable each custom extension in turn, and build a project-only selection. They relocate each prefix and run the packaged CLI and separately linked shared and static C clients. They check all stock modules, both ICUex collations, the project functions' arities and flags, and representative SQL results. The full preset also exercises an offline rebuild and confirms that a failed archive copy preserves the published package. To retain the last configuration and its source cache between test runs, pass `--build-root ./out-tests`.

| Stock source(s) | Availability checked on a fresh library connection |
|---|---|
| `compress`, `decimal`, `noop`, `regexp`, `remember`, `rot13`, `sha1`, `shathree`, `sqlar`, `uuid` | `compress`, `decimal`, `noop`, `regexpi`, `remember`, `rot13`, `sha1`, `sha3`, `sqlar_compress`, `uuid` |
| `csv`, `fuzzer`, `prefixes`, `series` | Virtual-table modules `csv`, `fuzzer`, `prefixes`, `generate_series` |
| `uint` | Collation `uint` |

| Project extension | SQL surface checked |
|---|---|
| ICUex | Collations `UTF_CI`, `UTF_CI_AI`, `str_casefold(text)`, `str_normalize(text, kind)` |
| PBLOB | `pblob_pack(json)`, `pblob_pack(json, format)`, `pblob_unpack(blob)` |
| RegexpMatches | `regexp_matches(pattern, text)`, `regexpi_matches(pattern, text)` |

The shell also registers several stock extensions itself. Use a library connection when verifying that a preset omits the stock modules. [Registration checks](./tests/test_presets.py)
