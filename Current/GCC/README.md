# Building SQLite with GCC on Linux

`sqlite_build.sh` builds a native SQLite CLI, shared library and static archive from SQLite's canonical source tree. The default build includes upstream ICU support, 15 stock `ext/misc` modules, and the ICUex, PBLOB and RegexpMatches project extensions. Applications get the selected extensions on each new SQLite connection.

## Build

Run from `Current/GCC` with Bash, GCC, GNU Make, binutils, `flock` and the standard GNU utilities available. Fetching and extracting sources uses `curl` and `unzip`. The harness uses `tclsh` if available or builds SQLite's bundled Jim interpreter. The ordinary build runs without Python.

```bash
./sqlite_build.sh
out/bin/sqlite3 :memory: "SELECT str_casefold('ABC'), typeof(pblob_pack('[1,2]')), regexp_matches('[0-9]+','a12b3');"
```

The full build returns `abc|blob|["12","3"]`. The script resolves its paths from its own directory and can be invoked from another working directory.

### Presets and switches

| `--preset` | Upstream ICU | Stock modules | Project extensions | Required system development packages |
|---|---|---|---|---|
| `bare` | Off | Off | Off | None |
| `bare-icu` | On | Off | Off | ICU |
| `bare-icu-ext` | On | All 15 | Off | ICU, zlib |
| `full` (default) | On | All 15 | ICUex, PBLOB, RegexpMatches | ICU, zlib |

Environment switches accept `0` or `1` and override the preset.

| Variable | Effect |
|---|---|
| `USE_ICU` | Enable SQLite's upstream ICU functions and ICU collations. |
| `SQLITE_EXTRA` | Build the 15 stock modules. `compress.c` and `sqlar.c` require zlib. |
| `USE_EXTRAS` | Enable the project hooks. Setting this to `0` skips all project downloads. |
| `SQLITE_ENABLE_ICUEX` | Select ICUex. Defaults to `USE_ICU` and requires ICU. |
| `SQLITE_ENABLE_PBLOB` | Select PBLOB. Defaults to `1` when project hooks run and fetches the FP16 headers. |
| `SQLITE_ENABLE_REGEXPMATCHES` | Select RegexpMatches. Defaults to `SQLITE_EXTRA` and requires stock `regexp.c`. |

```bash
OUT_DIR="$PWD/out-bare" ./sqlite_build.sh --preset bare
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

`OUT_DIR` defaults to `out/` beside the script.

| Path under `OUT_DIR` | Contents |
|---|---|
| `bin/` | `sqlite3` |
| `lib/` | Versioned `libsqlite3.so.<version>`, its `libsqlite3.so.0` and `libsqlite3.so` symlinks, and `libsqlite3.a` |
| `include/` | `sqlite3.h`, `sqlite3ext.h`, `sqlite3session.h` |
| `lib/pkgconfig/sqlite3.pc` | Relocatable consumer compile and link flags, including private library dependencies |
| `cache/` | SQLite source ZIP, selected project C files, and the FP16 ZIP for PBLOB |
| `sqlite/` | Extracted canonical SQLite sources |
| `build/` | Configured build tree, `tsrc/`, generated `sqlite3.c`, and `build-inputs.txt` with source digests, effective flags, compiler and dependency information |

`bin`, `include` and `lib` point into `package/`. The harness stages and checks the new distribution before switching the `package` symlink. To copy a complete prefix with its relative library symlinks, use `mkdir -p /path/to/prefix` and `cp -a out/package/. /path/to/prefix/`.

For a shared-library consumer, point `PKG_CONFIG_PATH` at the local `sqlite3.pc` and select the local library at runtime. For a static SQLite consumer, link `out/lib/libsqlite3.a` explicitly and retain the private system link flags from `pkg-config --static --libs sqlite3`. The installed CLI embeds its own copy of the customized amalgamation. The tests exercise the packaged libraries through separate C clients.

## Source preparation and reuse

Start at `main()` to follow the build in execution order. `collect_extensions()` selects the sources, `prepare_target_sources()` stages them for the amalgamation, and `publish_package()` switches the verified prefix into place. [Build driver](sqlite_build.sh)

The first build fetches SQLite's canonical `sqlite.zip`, the enabled project sources from their `main` branches and FP16 from `master` when PBLOB is selected. Downloads follow redirects, retry, and enter the cache only after a complete HTTP 200 response with a non-HTML body. Extraction checks the expected source files before publishing the source tree. A warm build reuses the cache and prepared inputs. To refresh a moving upstream source, move its cached file aside and run the build again. [SQLite source](https://sqlite.org/src/zip/sqlite.zip) · [ICUex](https://github.com/pchemguy/SQLiteICUex) · [PBLOB](https://github.com/pchemguy/SQLitePackedBlob) · [RegexpMatches](https://github.com/pchemguy/SQLiteRegexpMatches) · [FP16](https://github.com/Maratyszcza/FP16)

After `make .target_source`, the two Tcl helpers patch the selected extension initializers, generate `misc_ext_init.c` and bundle local headers. The ordered `EXTRA_SRC` list puts the stock regex engine before RegexpMatches, which uses its private definitions. Both PBLOB and RegexpMatches also use SQLite's private JSON code. The PBLOB hook declares `SQLITE_RESULT_SUBTYPE` on the staged `pblob_unpack` registration so the strict upstream CLI can return nested JSON. The cached upstream source stays available for subsequent builds.

The Bash hooks beside the driver run in filename order after the stock modules. A hook can use `project_source REPOSITORY BASENAME MACRO` to fetch a C file and add it to the amalgamation, or `add_source PATH MACRO` for a local file. Preparation callbacks run later, during `prepare_target_sources()`. The PBLOB hook assigns its FP16 archive path when it registers the callback so the callback can read it during staging. The driver rebuilds generated code when effective settings or inputs change and serializes builds using the same output root. [PBLOB hook](sqlite_ext_pblob.sh)

`./sqlite_build.sh clean` removes the managed source, build and package outputs while retaining `out/cache/`. Use a separate `OUT_DIR` to keep several presets available side by side.

## Verification

Run the cache and dependency tests and the native build matrix with Python, pytest, `pkg-config`, GCC and binutils available.

```bash
python3 -m pytest -v tests
```

The native tests build all four presets, disable each custom extension in turn, and build a project-only selection. They relocate each prefix and run the packaged CLI and separately linked shared and static C clients. They check all stock modules, both ICUex collations, the project functions' arities and flags, and representative SQL results. The full preset also exercises an offline rebuild and confirms that a failed archive copy preserves the published package. To retain the last configuration and its source cache between test runs, pass `--build-root /path/to/dedicated-test-output`.

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

The shell also registers several stock extensions itself. Use a library connection when verifying that a preset omits the stock modules. [Windows verification queries](../MSVC/README.md#post-build-registration-checks)
