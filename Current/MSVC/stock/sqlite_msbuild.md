---
url: https://chatgpt.com/c/6a786079-f408-83eb-87b1-e0d35b2804a5
---

# Building stock SQLite with MSVC on Windows

[sqlite_msbuild.bat](sqlite_msbuild.bat) builds the SQLite shell, DLL and static library with MSVC and SQLite's `Makefile.msc`. It generates an import library for the DLL and collects the distribution under `out\`. The default build includes ZLIB, ICU from an active Conda environment, and 15 stock SQLite extensions compiled into SQLite.

**One base directory is for one build.** Use a separate copy of the harness and its tool directory for each target architecture, build configuration or dependency installation. The script derives `out\` from the location of its tools, **not** from the directory where you invoke it. Starting another developer prompt in a different working directory does not isolate an x86 build from an x64 build.

## Run a build

1. Open an **x64** or **x86 Native Tools Command Prompt** with the MSVC C/C++ tools and Windows SDK installed (available with [Visual Studio or Build Tools](https://visualstudio.microsoft.com/downloads/)). Use Windows CMD.
2. For the default build, activate a Conda environment containing ICU for that same target architecture. To build without ICU, set `USE_ICU=0`; no Conda environment is then required.
3. From `Current\MSVC\stock` in your chosen base, run:

```cmd
sqlite_msbuild.bat
```

After a default build, check `out\bin` for `sqlite3.exe`, `sqlite3.dll`, `zlib1.dll` and the versioned ICU DLLs. For example, run `out\bin\sqlite3.exe :memory: "SELECT sqlite_version();"` to exercise the packaged shell. That does not test linkage against the packaged import library; see [Packaged artifacts](#packaged-artifacts).

### Build switches

Use `0` or `1`. Defaults apply when the variables are unset.

| Variable | Default | Effect |
|---|---:|---|
| `USE_ICU` | `1` | Stage Conda ICU, set the ICU include/library paths, add `SQLITE_ENABLE_ICU_COLLATIONS` and collect ICU runtime DLLs. |
| `USE_ZLIB` | `1` | Obtain and build ZLIB, or reuse it from this build; collect `zlib1.dll`. |
| `SQLITE_EXTRA` | `1` | Integrate the stock `ext\misc` modules. Any value other than `0` forces `USE_ZLIB=1`; only `1` runs the extension stage. |

For a build without ICU, ZLIB or stock extensions, run the following **in its own base**. Setting `USE_ZLIB=0` alone is not sufficient.

```cmd
set "USE_ICU=0"
set "SQLITE_EXTRA=0"
set "USE_ZLIB=0"
sqlite_msbuild.bat
```

These are the three feature switches in the stock harness. There is no ICU provider selector or ICU source-build fallback. It does not stage FP16, integrate project-specific extensions, or create a separate test build.

### NMake targets and diagnostics

```cmd
sqlite_msbuild.bat sqlite3.dll
sqlite_msbuild.bat clean
sqlite_msbuild.bat env
```

Ordinary arguments are forwarded to the **final** NMake invocation. A named target does not bypass environment checks, source preparation, initial `sqlite3.def` generation or subsequent import-library generation and collection. In particular, `clean` is an NMake target, not a reset of `out\`; later steps can fail if the target removed their inputs.

If the **first** argument is `env`, `tcl-env` or `tcl-test`, the harness runs that diagnostic against `out\sqlite\Makefile.msc` after preflight and option setup, **before** any download or extraction. The SQLite source tree must already exist. Once dispatched, the diagnostic returns **100** regardless of NMake's status and stops the normal build. An earlier preflight failure is a different exit path.

## Environment checks

[msbuild_check.bat](msbuild_check.bat) runs **once**, before architecture-specific paths are selected. It checks the local environment, not the cache or network.

| Check | Requirement |
|---|---|
| MSVC shell | `VisualStudioVersion` and `VCINSTALLDIR` must be set. `VSCMD_ARG_TGT_ARCH` must be `x86` or `x64` (case-insensitive). The host architecture is not used to select the target. |
| Executables on `PATH` | `cl.exe`, `nmake.exe`, `dumpbin.exe`, `lib.exe` and `curl.exe` are required, including on a warm build. The harness uses NMake, not `msbuild.exe`. |
| Windows tar | `%windir%\System32\tar.exe` must exist. A different `tar.exe` on `PATH` does not satisfy this check. |
| External Tcl | `tclsh.exe` on `PATH` is reported if present. Its absence is a **warning**, not an error. The harness sets `TCLSH_CMD` to `out\build\jimsh0.exe` for the stock extension tools; it does not search `TCL_HOME` or modify `PATH` to locate Tcl. |
| Conda ICU (`USE_ICU=1`) | After the preceding checks pass, `CONDA_PREFIX` must be set and `Library\bin` must contain a versioned `icuuc<digits>.dll`. `dumpbin /headers` checks each matching DLL's PE machine: `14C` for x86, `8664` for x64. A missing, unreadable or mismatched DLL fails preflight; a match is printed with its path, machine and target. This check also runs when the staged ICU tree already exists. |

The optional [pyenv bootstrap](pyenv/Anaconda.bat) downloads the `win-64` Micromamba executable; [conda_far.bat](pyenv/conda_far.bat) is the environment launcher. The SQLite harness does not install Conda or ICU. An x86 ICU build needs **both** an x86 MSVC prompt and a separately prepared x86 Conda environment with ICU. An x86 compiler paired with x64 ICU is not sufficient. To suppress console colors, set `NO_COLOR=1` or `NOCOLOR=1`.

## Build sequence and paths

The script locates `patch_sqlite_misc_autoext.tcl` beside the batch file or under `tool\`, `tools\` or `extra\`. Its directory becomes `TOOLDIR`; the parent is `PROJDIR`. In the repository layout, `PROJDIR` is `Current\MSVC\stock`. Paths below are relative to that base.

| Order | Stage | Main location or result |
|---:|---|---|
| 1 | Create output directories, run preflight, set dependency and SQLite options; dispatch a diagnostic if requested | `out\`, `out\build`, `out\build\tsrc` |
| 2 | Obtain and extract the SQLite snapshot | `out\cache\sqlite.zip` → `out\sqlite` |
| 3 | If ZLIB is enabled, obtain, stage and build it | `out\cache\zlib.tar.gz` → `out\sqlite\compat\zlib` |
| 4 | If ICU is enabled, stage or validate the Conda files | `%CONDA_PREFIX%\Library` → `out\sqlite\compat\icu` |
| 5 | Run `.target_source` from the build directory; prepare stock extensions if enabled | `out\build\tsrc` |
| 6 | Generate exports, run the requested SQLite build, regenerate the import library, then collect available artifacts | `out\build` → `out\bin`, `out\include`, `out\lib` |

### Downloads and cache

| Component | On a cache miss | Cache target |
|---|---|---|
| SQLite | Fetch `https://sqlite.org/src/zip/sqlite.zip` (a source snapshot, not a pinned release). | `out\cache\sqlite.zip` |
| ZLIB | Follow `https://github.com/madler/zlib/releases/latest` and record the effective URL in `out\cache\zlib-release-url.txt`. Check cURL's status and require this repository's `/releases/tag/v<version>` with a dotted numeric version before requesting `/releases/download/v<version>/zlib-<version>.tar.gz`. | `out\cache\zlib.tar.gz` |

If the target file exists, the download stage returns success without inspecting its contents or contacting the server. For ZLIB this also skips the latest-release lookup. There is no automatic refresh, hash check, ETag check or version comparison. For repeatable builds, retain the exact archives and record the Conda package versions, MSVC toolset and build settings.

The shared [download_file.bat](download_file.bat) interface is `download_file.bat "NAME" "TARGET" "URL"`. On a miss, it downloads into `<target>.part` using a redirect-following GET with retries, not a separate HEAD request. It requires a successful cURL exit and final HTTP status `200` and rejects `text/html` irrespective of case or media-type parameters before renaming the partial file to the final name. A missing or generic content type is not by itself an error. A leftover `.part` is never a cache hit.

Download progress and errors go to the console on stderr. In `out\cache`, the response-header chain is written to `sqlite.log` or `zlib.tar.log`; final status and content type go to `sqlite.zip.response.log` or `zlib.tar.gz.response.log`. These are distinct from the release URL log. The harness removes old `out\stdout.log` and `out\stderr.log` during setup; it does not record a general build transcript in them.

### SQLite extraction

[extract_archive.bat](extract_archive.bat) takes `"NAME" "FLAG" "SRC" "DST"`. `FLAG` is the on-disk path of a file or directory supplied by the archive. Paths are resolved relative to the caller. After checking that the archive file and destination directory exist, the helper skips extraction if `FLAG` exists. Otherwise it runs `"%TAR%" -x -f "%SRC%" -C "%DST%"` without changing the working directory and returns tar's status. When called independently with `TAR` unset, it uses `%SystemRoot%\System32\tar.exe`. With the optional `/stage` argument, the destination must not already exist; the helper creates it only when extraction is needed.

For SQLite, the flag is `out\sqlite\Makefile.msc`, supplied by `sqlite.zip`. Its presence skips extraction; it does not prove that every other file was extracted.

### ZLIB staging and build

On first use, `:ZLIB_EXTRACT` extracts into a fresh `out\sqlite\compat\zlib.stage`. It requires exactly one top-level entry: a directory named `zlib-<dotted-numeric-version>` containing `win32\Makefile.msc`. It moves that directory to `compat\zlib`. No online lookup is needed to determine the extracted directory name.

The extractor requires the cached archive on every run. If `compat\zlib\win32\Makefile.msc` already exists, it skips extraction without creating `zlib.stage`. If `compat\zlib\zlib1.dll` is absent, the harness invokes `Makefile.msc`'s `zlib` target; otherwise it reuses the DLL.

### Conda ICU staging

Conda is the only ICU source in this harness. The project uses its packaged ICU data because an earlier Windows source build linked against stub data. The staging checks below establish file presence, nonzero size and matching runtime names; they do **not** exercise a data-dependent ICU operation.

On first use, `:ICU_CONDA` checks for `%CONDA_PREFIX%\python.exe` and `%CONDA_PREFIX%\Library\bin\icuinfo.exe`. Neither executable is run. It copies one installation into a fresh `out\sqlite\compat\icu.stage`, removes unversioned `icu??.dll` and `icutest*.dll` there, validates the set, writes `.icu-staged`, then renames the directory to `icu`. Compilation, linking and packaging continue to use the established paths:

| Source under `%CONDA_PREFIX%\Library` | Destination under `out\sqlite\compat\icu` for x86 | Destination for x64 |
|---|---|---|
| `include\unicode\` (header tree) | `include\unicode\` | `include\unicode\` |
| `lib\icu??.lib` | `lib\` | `lib64\` |
| `bin\icu*.dll` and `bin\icuinfo.exe` | `bin\` | `bin64\` |

A valid set contains exactly one versioned common DLL (`icuuc<digits>.dll`) and these nonempty files:

- Headers: `unicode\utypes.h`, `unicode\ucol.h`, `unicode\uregex.h` and `unicode\ustring.h`.
- Import libraries: `icudt.lib`, `icuuc.lib` and `icuin.lib`.
- Runtime: `icuinfo.exe`, the common DLL, and `icuin<digits>.dll` and `icudt<digits>.dll` with the **same suffix** as the common DLL.

On later runs, the harness requires `.icu-staged` and revalidates the files already staged. It does not fill missing components from the active prefix or refresh them when Conda changes. Only runtime DLLs are collected into `out\bin`; the staged ICU headers, import libraries and `icuinfo.exe` stay in the compatibility tree.

## SQLite build settings and stock extensions

`:BUILD_OPTIONS` sets `SESSION=1`, `RBU=1`, `API_ARMOR=1` and `SYMBOLS=0`. The script does not set `NO_TCL` or `WITHOUT_JIMSH`. It initializes `EXTRA_SRC` empty and constructs `OPT_XTRA` itself; an inherited `OPT_XTRA` is cleared during setup. The base definitions are:

```text
SQLITE_ENABLE_NORMALIZE           SQLITE_ENABLE_FTS4=1
SQLITE_ENABLE_FTS3_PARENTHESIS    SQLITE_ENABLE_FTS3_TOKENIZER
SQLITE_ENABLE_EXPLAIN_COMMENTS=1  SQLITE_ENABLE_OFFSET_SQL_FUNC=1
SQLITE_ENABLE_QPSG                SQLITE_ENABLE_STAT4
SQLITE_DQS=0                      SQLITE_LIKE_DOESNT_MATCH_BLOBS
SQLITE_MAX_EXPR_DEPTH=100         SQLITE_MAX_ATTACHED=100
SQLITE_OMIT_DEPRECATED            SQLITE_DEFAULT_FOREIGN_KEYS=1
SQLITE_DEFAULT_SYNCHRONOUS=1      SQLITE_USE_URI=1
SQLITE_SOUNDEX
```

`USE_ICU=1` also adds `SQLITE_ENABLE_ICU_COLLATIONS`. With `SQLITE_EXTRA=1`, `:EXTRA_SRC_STOCK` uses `out\build\jimsh0.exe` and SQLite's `tool\cp.tcl` to copy the following `ext\misc` modules into `tsrc`. The corresponding definitions are:

| Sources | Compile definitions, in the same order |
|---|---|
| `compress.c`, `csv.c`, `decimal.c`, `fuzzer.c`, `noop.c` | `SQLITE_ENABLE_COMPRESS`, `SQLITE_ENABLE_CSV`, `SQLITE_ENABLE_DECIMAL`, `SQLITE_ENABLE_FUZZER`, `SQLITE_ENABLE_NOOP` |
| `prefixes.c`, `regexp.c`, `remember.c`, `rot13.c`, `series.c` | `SQLITE_ENABLE_PREFIXES`, `SQLITE_ENABLE_REGEXP`, `SQLITE_ENABLE_REMEMBER`, `SQLITE_ENABLE_ROT`, `SQLITE_ENABLE_SERIES` |
| `sha1.c`, `shathree.c`, `sqlar.c`, `uint.c`, `uuid.c` | `SQLITE_ENABLE_SHA`, `SQLITE_ENABLE_SHATHREE`, `SQLITE_ENABLE_SQLAR`, `SQLITE_ENABLE_UINT`, `SQLITE_ENABLE_UUID` |

In `tsrc`, [patch_sqlite_misc_autoext.tcl](tool/patch_sqlite_misc_autoext.tcl) adapts the extensions for built-in registration and generates `misc_ext_init.c`. Then [bundle_extra_src.tcl](tool/bundle_extra_src.tcl) inlines local source dependencies. The harness passes the 15 translation units and `misc_ext_init.c` to NMake through `EXTRA_SRC` and sets `SQLITE_EXTRA_AUTOEXT=sqlite3ExtraAutoExtInit`. These modules do not require separate loadable-extension DLLs.

## Exports and import library

From `out\build`, `:SQLITE_BUILD` runs NMake for `sqlite3.def` with the selected `EXTRA_SRC`. It then replaces the generated definition file: it writes `EXPORTS`, filters `dumpbin /linkermember:2 libsqlite3.lib` into `exports.txt`, appends the sorted names to `sqlite3.def` and removes `exports.txt`. The harness then runs NMake with the caller's arguments and recreates `sqlite3.lib` with `lib.exe` using `/machine:%VSCMD_ARG_TGT_ARCH%`.

The export list is not independently validated, and the temporary list is opened for append. After an interrupted run, do not assume the next `.def` is complete or free of stale entries. For a binary distribution, inspect the actual DLL exports and link and run a client against the packaged import library in the matching MSVC environment.

## Packaged artifacts

| Files collected | Destination | Use |
|---|---|---|
| `sqlite3.exe`, `sqlite3.dll` | `out\bin` | Command-line shell and SQLite runtime |
| `zlib1.dll`, `icu*.dll` | `out\bin` | Runtime dependencies when the respective features are enabled |
| `sqlite3*.h` from `out\build` | `out\include` | Generated SQLite headers; project `src\*.h` files are not collected |
| `sqlite3.def`, `sqlite3.lib` | `out\lib\import` | Export definition and import library for linking against `sqlite3.dll` |
| `libsqlite3.lib` | `out\lib\static` | Static SQLite library, not the DLL import library |

**Collection is best effort.** `:COLLECT_BINARIES` clears files directly under `out\bin` before copying available products. It does not clear the include or library directories, so older files can remain there. The collector returns success even if an expected artifact is absent or a copy fails. Exit `0` is **not** a guarantee of a complete or current distribution; check the files required by your consumer. Do not keep unrelated files in `out\bin`.

## Recovery and reproducibility

| Situation | Action |
|---|---|
| You need to download a cached file again | Move the existing target file out of the cache, then rerun the build. |
| SQLite extraction was interrupted | Move the incomplete `out\sqlite` tree aside and rerun with the cached ZIP. Otherwise an already extracted `Makefile.msc` will cause extraction to be skipped. The tree also contains staged dependencies. |
| A final ICU or ZLIB tree fails validation | Move the affected `compat\icu` or `compat\zlib` tree aside. Do not manufacture the missing files. |
| Staging stopped and left `icu.stage` or `zlib.stage` | Inspect the named staging directory and move it aside before retrying. Fresh staging requires a new directory; the harness does not merge its contents. |
| You need a different architecture, feature configuration, dependency version or clean source snapshot | Start in a separate clean base. Replacing a cached archive alone does not invalidate an already completed extraction or rebuild its dependent artifacts. |

Most build stages stop on error; the diagnostic status and best-effort collection described above are exceptions to interpreting the final status as a build result. A fully cached normal build does not fetch upstream releases, but it still needs the local tools and, if enabled, the matching active Conda ICU. To reset the **same** build completely, move aside that base's generated `out` directory after retaining any artifacts you need.

## Harness tests

From `Current\MSVC\stock` in a Windows MSVC developer prompt with Python and pytest available:

```cmd
python -m pytest tests
```

The [cache tests](tests/test_download_cache.py) use a loopback HTTP server; the [preflight tests](tests/test_msbuild_check.py) cover target selection and PE-machine checking; the [staging tests](tests/test_dependency_staging.py) cover explicit extraction destinations, reuse of extracted files, ZLIB release handling and ICU set validation. Some cases require real MSVC tools. These tests do not replace a native end-to-end build and link test for each target architecture.
