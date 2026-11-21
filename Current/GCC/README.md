# Porting the SQLite build harness to Linux

Build the customized SQLite CLI, shared library and static library with Bash, GCC and SQLite's canonical Unix makefiles. Keep the local `out/` layout, the four feature presets and the extensions built into each SQLite connection. Use the host package manager for ICU and zlib. The Windows baseline for this plan is [the MSVC harness at `77c8dbd`](https://github.com/pchemguy/SQLite-ICU-MinGW/tree/77c8dbd26d322b4bb541c2f351b67e824a418be4/Current/MSVC).

## Entry point and presets

Use `./sqlite_build.sh [--preset NAME]` as the entry point. Running it without arguments selects `full`. Resolve paths from the script directory so it can be invoked from any working directory. Default the build root to `Current/GCC/out` and allow `OUT_DIR` to select another root for a different configuration or native architecture. The upstream configure script rejects spaces in source and build paths. Use a space-free `OUT_DIR` when the checkout path contains spaces.

| Preset | Built-in ICU | Stock `ext/misc` | Project extensions | System development packages to ensure |
|---|---|---|---|---|
| `bare` | Off | Off | Off | None |
| `bare-icu` | On | Off | Off | ICU |
| `bare-icu-ext` | On | On | Off | ICU, zlib |
| `full` | On | On | ICUex, PBLOB, RegexpMatches | ICU, zlib |

Retain `USE_ICU`, `SQLITE_EXTRA`, `USE_EXTRAS`, `SQLITE_ENABLE_ICUEX`, `SQLITE_ENABLE_PBLOB` and `SQLITE_ENABLE_REGEXPMATCHES`. Accept `0` and `1` as environment overrides for the preset defaults. `USE_EXTRAS=0` skips all project hooks and their downloads. Derive the zlib requirement from the selected components. The stock set includes `compress.c` and `sqlar.c`, both of which call zlib.

## What changes on Linux

| Windows workflow | Linux design |
|---|---|
| `msbuild_check.bat`, Native Tools prompt, Windows SDK and PE machine checks | Use the active `gcc`, GNU `make` and `ar`. Check the tools needed by the selected stage and let `configure` probe the compiler and linker. Record `gcc -dumpmachine` for the build. Omit the separate environment-check script and x86/x64 directory logic. |
| Conda bootstrap and activation, `.icu-staged`, ICU DLL suffix checks and copies | Discover the distro's ICU development files with `pkg-config`. Install them when missing. The Linux loader resolves ICU and its data from the host. |
| `USE_ZLIB`, latest-release lookup, source download, compilation and collection of `zlib1.dll` | Resolve the distro's zlib development package when a selected component requires it. Let the system loader find `libz`. |
| `download_file.bat`, Windows `tar.exe`, `copy`/`xcopy` and directory-search fallbacks | Keep the cache guarantees in Bash. Use `curl` on cache misses, `unzip` for the SQLite and FP16 ZIPs, and ordinary `mkdir`, `cp` and `install`. |
| `Makefile.msc`, `nmake` diagnostics and four batch launchers | Configure out of tree and use GNU Make. One Bash entry point selects the four presets. Keep `clean` independent of fetching, compiling and packaging. Return the failing command's status. |
| `dumpbin`, `.def`, `lib.exe`, separate import-library and static-library directories | Produce an ELF shared object with a SONAME, its linker symlink and a static archive in `out/lib/`. Verify them by linking consumers. |
| `pyenv/`, DLL-path discovery, test-API generator and auxiliary scripts | The normal build uses the two Tcl source-transformation tools. Leave the Windows environment launchers, optional test-API tooling and unused copy/replace helpers out of the Linux build path. Python is needed for the pytest harness tests. |

### Dependency installation

With ICU enabled, probe `pkg-config --exists icu-io`. This is the module SQLite requests with `--with-icu-config=pkg-config`. Pass that option together with `--enable-icu-collations` to retain both upstream ICU support and its collation support. When stock extensions are selected, probe `pkg-config --exists zlib` and confirm that configure found `zlib.h` and `-lz`. Run package-manager operations only for missing requirements. With ICU disabled, leave its opt-in configure flags unset. [SQLite ICU configuration](https://github.com/sqlite/sqlite/blob/5672ed86435140683ce66b12d021e5941c4cee48/autosetup/sqlite-config.tcl#L1392-L1487)

| Initial package-manager support | Missing ICU development files | Missing zlib development files |
|---|---|---|
| Debian / Ubuntu | `apt-get install -y libicu-dev` | `apt-get install -y zlib1g-dev` |
| Fedora / RHEL family with DNF | `dnf install -y libicu-devel` | `dnf install -y 'pkgconfig(zlib)'` |

If the `pkg-config` command itself is missing on a build that needs it, install the provider first. Install the missing development packages together as root or via `sudo`. Refresh APT indexes when needed, then recheck the modules before configuring. If installation fails or privileges are unavailable, stop with the package name and installation command. Other distributions can build with the same modules already installed. Run the rest of the build as the invoking user. ICU and zlib runtime libraries stay in the host library paths. [Debian ICU](https://packages.debian.org/trixie/amd64/libicu-dev/filelist) · [Debian zlib](https://packages.debian.org/trixie/amd64/zlib1g-dev/filelist) · [Fedora ICU](https://packages.fedoraproject.org/pkgs/icu/libicu-devel/) · [Fedora zlib compatibility package](https://packages.fedoraproject.org/pkgs/zlib-ng/zlib-ng-compat-devel/)

**In `bare` and `bare-icu`, zlib is optional.** Skip the zlib package request in these presets. Upstream configure already detects usable zlib headers and libraries. When available, the shell can use them for ZIP/archive support. When absent, the bare presets can proceed. Keep upstream's resulting flags and record the detected configuration so the runtime dependencies of a particular build are visible. [Upstream zlib probe](https://github.com/sqlite/sqlite/blob/5672ed86435140683ce66b12d021e5941c4cee48/autosetup/sqlite-config.tcl#L682-L692) · [Shell source](https://github.com/sqlite/sqlite/blob/5672ed86435140683ce66b12d021e5941c4cee48/src/shell.c.in#L285-L307)

## Source preparation and compilation

1. **Fetch only selected inputs.** Keep the existing SQLite canonical source snapshot and project source URLs. Cache `sqlite.zip`, the enabled hooks' C files and the FP16 archive for PBLOB in `out/cache/`. Reuse completed downloads offline. On a miss, follow redirects, retry, require a successful final HTTP 200, reject HTML, and rename the completed `.part` file into place. Extract ZIPs into a temporary directory and publish only after checking the expected files. For SQLite these include `configure`, `main.mk` and `tool/mksqlite3c.tcl`. Keep the extracted tree at `out/sqlite/`. Capture source IDs or cached file digests so a build using moving upstream refs can be identified.
2. **Configure and generate sources.** From `out/build/`, run `../sqlite/configure` with `CC=gcc`, `CFLAGS=-O2`, the local `out/` prefix, `--enable-shared`, `--enable-static`, `--soname=legacy` and `--disable-rpath`. The distribution targets can use `--disable-tcl` to skip the optional SQLite Tcl bindings. Map `SESSION=1` to `--enable-session` (including the preupdate hook), and carry across `SQLITE_ENABLE_RBU`, `SQLITE_ENABLE_API_ARMOR` and the full `:BUILD_OPTIONS` list. Also account for features inherited from `Makefile.msc`, including FTS5, RTree/Geopoly, column metadata and the diagnostic virtual tables. Pass additional definitions through `make OPTIONS=...` from the first `.target_source` invocation through compilation so generated parser code, CLI and libraries see the intended options. [Harness flags](../MSVC/sqlite_msbuild.bat) · [MSVC defaults](https://github.com/sqlite/sqlite/blob/5672ed86435140683ce66b12d021e5941c4cee48/Makefile.msc#L381-L425) · [Unix build rules](https://github.com/sqlite/sqlite/blob/5672ed86435140683ce66b12d021e5941c4cee48/main.mk#L243-L277)
3. **Prepare built-ins after `make .target_source`.** This target recreates `out/build/tsrc`. Stage pristine extension sources there after it completes. Use the existing `patch_sqlite_misc_autoext.tcl` and `bundle_extra_src.tcl` from that directory with basenames and either a suitable `tclsh` or SQLite's host-built Jim interpreter. Include byte-identical copies of the two portable helpers in `Current/GCC/tool/` so the GCC harness can be copied independently. Keep the MSVC list of 15 modules and their exact enable macros, including the `rot13.c` → `SQLITE_ENABLE_ROT` and `sha1.c` → `SQLITE_ENABLE_SHA` mappings. [Stock module list](../MSVC/README.md#sqlite-build-settings-and-stock-extensions) · [Source preparation rule](https://github.com/sqlite/sqlite/blob/5672ed86435140683ce66b12d021e5941c4cee48/main.mk#L1079-L1096)
4. **Assemble one ordered extension list.** Adapt `sqlite_ext_*.bat` to Bash hooks discovered as `sqlite_ext_*.sh`, with stable order and a shared list of staged source files and definitions. ICUex requires ICU. PBLOB requires SQLite JSON and the extracted FP16 headers, which the bundler inlines. RegexpMatches requires SQLite JSON and the private definitions in stock `regexp.c`, which must appear first. With project hooks enabled, default ICUex on when ICU is selected and RegexpMatches on when the stock set is selected. Reject an explicit request that cannot be satisfied. Generate one fresh `misc_ext_init.c` for the selected set, append it once, and set `SQLITE_EXTRA_AUTOEXT=sqlite3ExtraAutoExtInit` whenever the set is nonempty. This also permits PBLOB or ICUex with the stock set disabled. [Project hooks](../MSVC/README.md#project-extension-hooks)
5. **Build and collect.** Pass the same ordered `EXTRA_SRC` list (build-relative `tsrc/...` paths) to the GNU Make targets for `sqlite3.c`, `sqlite3`, `libsqlite3.so` and `libsqlite3.a`. Keep the upstream CLI recipe. Validate and publish the required files as a set. A missing library, failed copy or dangling link fails the build. Record the effective settings, compiler target and dependency versions for each output root. When the inputs or settings change, regenerate from pristine sources and replace the managed package files. Separate `OUT_DIR` values retain multiple configurations side by side. `clean` preserves the download cache. [Amalgamation rule](https://github.com/sqlite/sqlite/blob/5672ed86435140683ce66b12d021e5941c4cee48/main.mk#L1146-L1150) · [CLI recipe](https://github.com/sqlite/sqlite/blob/5672ed86435140683ce66b12d021e5941c4cee48/main.mk#L2215-L2229)

## Local products

| Location | Contents |
|---|---|
| `out/cache/`, `out/sqlite/`, `out/build/tsrc/` | Reusable downloads, extracted canonical sources and prepared sources, respectively. `out/build/` also holds the generated amalgamation and intermediate build files. |
| `out/bin/` | `sqlite3` |
| `out/lib/` | `libsqlite3.so.<SQLite-version>` with SONAME `libsqlite3.so.0`, relative `libsqlite3.so.0` and `libsqlite3.so` symlinks, and `libsqlite3.a` |
| `out/include/` | `sqlite3.h`, `sqlite3ext.h` and `sqlite3session.h` from the matching source/build |
| `out/lib/pkgconfig/` | `sqlite3.pc` with `prefix=${pcfiledir}/../..` and private dependencies reflecting the actual build |

The static archive contains SQLite and the selected extensions. Its consumers supply the system libraries recorded in `sqlite3.pc`. The upstream CLI embeds its own copy of SQLite, so a separate C client must exercise the packaged shared library.

## Implementation order and acceptance

| Increment | Acceptance |
|---|---|
| 1. Local driver, cache and `bare` | Invoke from another directory, repeat from a warm cache with networking disabled, and recover from interrupted downloads or extraction. Run on hosts with and without zlib development files. The bare build requests neither ICU nor zlib and works in both cases. |
| 2. System dependencies and `bare-icu` | Exercise preinstalled and missing ICU on APT and DNF, including installation failure. Confirm that this preset provisions only ICU. Run `lower('I','tr_TR')` and verify U+0131. |
| 3. Stock extensions and project hooks | Build `bare-icu-ext` and `full`, including a host that needs the zlib development package installed. Exercise `uncompress(compress(...))`, PBLOB pack/unpack, ICUex folding/collations and both RegexpMatches functions. Compare registered functions, arities and flags with the Windows post-build queries. Exercise each hook disabled and a project-only build. [Expected registrations](../MSVC/README.md#post-build-registration-checks) |
| 4. Packaged consumers and rebuilds | Link and run separate C clients against the local shared object and the explicit static archive. Verify the shared client's resolved SQLite path and the library SONAME with `ldd`/`readelf`. Query a fresh library connection for registrations and portable compile options, including in `bare`, since the CLI supplies some stock functions itself. Move the output prefix and repeat the consumer test. Require a nonzero exit on packaging failure and check for stale artifacts when changing presets. |

## Feasibility checks performed during planning

On Debian x86-64 with GCC 14.2, the existing Tcl tools processed all 15 stock modules and all three project modules. A focused compile used the SQLite 3.54.1 release amalgamation, matching stock sources, Debian ICU development headers and the host ICU 76 and zlib runtimes. A fresh connection to the shared library exposed all 18 modules. The CLI and separately linked shared and static C consumers returned `abc`, `blob` and `["12","3"]` from the Windows smoke query. The shared client resolved SQLite from the local `out/lib/` and ICU and zlib from system paths.

A separate run of the canonical configure script detected the installed zlib development files and added the compiler and linker flags for the shell and library automatically. The complete cold build from a canonical source archive, automatic package installation and the four-preset matrix are acceptance work for implementation.
