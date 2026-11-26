---
urls:
  - https://chatgpt.com/c/6a9e37b0-95bc-83eb-9a9d-5cc7db64b388
  - https://chatgpt.com/c/6a786079-f408-83eb-87b1-e0d35b2804a5
---

# Building SQLite with MSVC on Windows

## Overview

[sqlite_msbuild.bat](sqlite_msbuild.bat) builds a customized SQLite distribution for x86 or x64 Windows using MSVC and SQLite’s `Makefile.msc`. Smaller [presets](#presets) use the same harness. The default build:

- Builds or reuses ZLIB and stages ICU from the active Conda environment.
- Compiles 15 stock SQLite `ext/misc` modules and three project extensions into the SQLite amalgamation (`sqlite3.c`): [ICUex](https://github.com/pchemguy/SQLiteICUex), [PBLOB](https://github.com/pchemguy/SQLitePackedBlob), and [RegexpMatches](https://github.com/pchemguy/SQLiteRegexpMatches). The PBLOB hook stages its FP16 headers.
- Registers the extensions’ SQL functions and collations through a generated dispatcher when each connection opens. Applications do not need to load separate extension DLLs.
- Packages the shell, runtime DLLs, SQLite headers, static library, and import library for `sqlite3.dll` under `out\`.

**One base directory is for one build.** Use a separate copy of the harness and its tools for each target architecture, build configuration or dependency installation. Output paths are relative to `sqlite_msbuild.bat`, not the caller's current directory. Opening another developer prompt in a different directory does not isolate an x86 build from an x64 build.

## Run a build

1. Use Windows CMD with the MSVC C/C++ tools and Windows SDK installed (available with [Visual Studio or Build Tools](https://visualstudio.microsoft.com/downloads/)). You may start from an already initialized **x64** or **x86 Native Tools Command Prompt**. If no MSVC environment is active, [msbuild.bat](msbuild.bat) can discover and activate an **x64** toolchain automatically; x86 builds require an already initialized x86 MSVC prompt.
2. For the default build, activate a Conda environment containing ICU for the same target architecture. For a build without ICU or Conda, use the [bare preset](#presets). For a custom build without ICU, set `USE_ICU=0` and also set either `SQLITE_ENABLE_ICUEX=0` (skip ICUex) or `USE_EXTRAS=0` (skip all project hooks).
3. From a directory containing a copy of the build harness, run:

```cmd
sqlite_msbuild.bat
```

After a default build, check `out\bin` for `sqlite3.exe`, `sqlite3.dll`, `zlib1.dll` and the versioned ICU DLLs. For example, run `out\bin\sqlite3.exe :memory: "SELECT sqlite_version();"` to exercise the packaged shell. That does not test linkage against the packaged import library; see [Packaged artifacts](#packaged-artifacts).

### Harness

The build harness includes

- `sqlite_msbuild.bat`: Main script.
- `msbuild.bat`: MSVC discovery, activation and verification helper. It reuses an active x86/x64 MSVC environment or, when none is active, discovers and activates x64 Build Tools/Visual Studio before validating the compiler, linker and supporting tools.
- `download_file.bat`: cURL download helper.
- `extract_archive.bat`: tar archive extraction helper.
- `sqlite_ext_icuex.bat`:  [ICUex](https://github.com/pchemguy/SQLiteICUex) extension activation.
- `sqlite_ext_pblob.bat`: [PBlob](https://github.com/pchemguy/SQLitePackedBlob) extension activation.
- `sqlite_ext_regexpmatches.bat`: [RegexpMatches](https://github.com/pchemguy/SQLiteRegexpMatches) extension activation.
- `tool/`: additional helper scripts.

### Switches

Use `0` or `1`. Defaults apply when the variables are unset.

| Variable       | Default | Effect                                                                                                                                                                      |
| -------------- | ------: | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `USE_ICU`      |     `1` | Stage Conda ICU, set the ICU include/library paths, add `SQLITE_ENABLE_ICU_COLLATIONS` and collect ICU runtime DLLs.                                                        |
| `USE_ZLIB`     |     `1` | Obtain and build ZLIB, or reuse it from this build; collect `zlib1.dll`.                                                                                                    |
| `SQLITE_EXTRA` |     `1` | Integrate the stock `ext\misc` modules. Any value other than `0` forces `USE_ZLIB=1`; only `1` runs the extension stage.                                                    |
| `USE_EXTRAS`   |     `1` | Run the [project extension hooks](#project-extension-hooks) for ICUex, PBLOB and RegexpMatches. Set to `0` to skip all three without changing `SQLITE_EXTRA` or `USE_ZLIB`. |

Stock and project extensions have separate switches but share a registration mechanism. Keep `SQLITE_EXTRA=1` for the shipped project hooks: the stock stage supplies the [dispatcher](#how-extensions-enter-the-amalgamation), even for project extensions that do not use a stock module. RegexpMatches also needs the stock `regexp.c` itself. ICUex needs `USE_ICU=1`; PBLOB stages its own FP16 headers. To omit just one project extension, use its [individual switch](#project-extension-hooks).

### Presets

Run one launcher from its own build base:

| Launcher                                                                       | Conda ICU | ZLIB | Stock `ext/misc` | Project extensions |
| ------------------------------------------------------------------------------ | --------- | ---- | ---------------- | ------------------ |
| [sqlite_msbuild_bare.bat](sqlite_msbuild_bare.bat)                             | No        | No   | No               | None               |
| [sqlite_msbuild_bare_icu.bat](sqlite_msbuild_bare_icu.bat)                     | Yes       | No   | No               | None               |
| [sqlite_msbuild_bare_icu_ext.bat](sqlite_msbuild_bare_icu_ext.bat)             | Yes       | Yes  | Yes              | None               |
| [sqlite_msbuild_bare_icu_ext_extra.bat](sqlite_msbuild_bare_icu_ext_extra.bat) | Yes       | Yes  | Yes              | All three          |

The launchers set their switches and call `sqlite_msbuild.bat` without forwarding arguments. Invoke the main script directly for a custom selection or NMake target. For example, to build the default configuration except for PBLOB and its FP16 headers, start in a fresh base and run:

```cmd
set "SQLITE_ENABLE_PBLOB=0"
sqlite_msbuild.bat
```

### NMake targets and diagnostics

Invocation: `sqlite_msbuild.bat [NMAKE_TARGET_OR_OPTION ...]`. For example:

```cmd
sqlite_msbuild.bat sqlite3.dll
sqlite_msbuild.bat clean
sqlite_msbuild.bat env
```

Ordinary arguments are forwarded to the **final** NMake invocation. A named target does not bypass environment checks, source preparation, initial `sqlite3.def` generation or subsequent import-library generation and collection. In particular, `clean` is an NMake target, not a reset of `out\`; later steps can fail if the target removed their inputs.

If the **first** argument is `env`, `tcl-env` or `tcl-test`, the harness runs that diagnostic against `out\sqlite\Makefile.msc` after preflight and option setup, **before** any download or extraction. The SQLite source tree must already exist. Once dispatched, the diagnostic returns **100** regardless of NMake's status and stops the normal build. An earlier preflight failure is a different exit path.

## MSVC activation and environment verification

[msbuild.bat](msbuild.bat) runs **once** near the start of the SQLite harness, before architecture-specific dependency paths are selected. Despite its name, it does not build SQLite with MSBuild and does not install Visual Studio or Build Tools. Its job is to establish or validate the MSVC command-line environment required by the NMake build.

If `VSINSTALLDIR` is already defined, the helper treats the MSVC environment as active and proceeds directly to verification. This preserves an explicitly selected x86 or x64 Native Tools environment.

If no MSVC environment is active, the helper searches for `vcvars64.bat` and activates an x64 toolchain. Discovery proceeds through an explicit `VCVARS` setting or `vcvars64.bat` on `PATH`, installed Visual Studio locations, local/sibling Build Tools locations, and the `MSBUILDTOOLS`, `BUILDTOOLS`, and `MSBUILD` directory variables. Automatic discovery activates **x64**; use an already initialized x86 Native Tools Command Prompt for x86 builds.

After reuse or activation, the helper verifies the resulting environment:

| Check | Requirement |
|---|---|
| MSVC environment | `VisualStudioVersion` must be set and `VCINSTALLDIR` must name an existing location. `VSCMD_ARG_TGT_ARCH` must be `x86` or `x64` (case-insensitive). The host architecture is not used to select the target. |
| Required executables | `cl.exe`, `nmake.exe`, `link.exe`, `lib.exe`, `dumpbin.exe` and `curl.exe` must resolve on `PATH`, including on a warm build. SQLite itself is built with NMake, not `msbuild.exe`. |
| Microsoft linker | The resolved `link.exe` must identify as the Microsoft Incremental Linker. The helper also compares its location with the active `cl.exe` toolset and detects common MSYS/Git/Conda linker collisions. |
| Linker collision recovery | For the supported local Conda/MSYS layout, the helper may rename the conflicting `Library\usr\bin\link.exe` to `link_.exe`, resolve `link.exe` again, and require the recovered linker to be the Microsoft linker from the compiler directory. Unsupported collisions fail with guidance for manual resolution. |
| Windows tar | `%windir%\System32\tar.exe` must exist. A different `tar.exe` on `PATH` does not satisfy this check. |
| External Tcl | `tclsh.exe` on `PATH` is reported if present. Its absence is a **warning**, not an error. The SQLite harness sets `TCLSH_CMD` to `out\build\jimsh0.exe` for the stock extension tools; it does not search `TCL_HOME` or modify `PATH` to locate Tcl. |
| Conda ICU (`USE_ICU=1`) | `CONDA_PREFIX` must be set and `Library\bin` must contain a versioned `icuuc<digits>.dll`. `dumpbin /headers` checks each matching DLL's PE machine: `14C` for x86, `8664` for x64. A missing, unreadable or mismatched DLL fails verification; a match is printed with its path, machine and target. This check also runs when the staged ICU tree already exists. |

During the build, `nmake.exe` drives `Makefile.msc`, `cl.exe` compiles the generated SQLite source, and `link.exe` links the DLL and shell. `dumpbin.exe` serves two purposes: identifying the ICU DLL architecture during verification and listing symbols from the static SQLite library during export generation. `lib.exe` turns the resulting export definition into the DLL import library. Downloads use `curl.exe`, extraction uses Windows tar, and the harness runs its Tcl source-preparation tools with SQLite's `jimsh0.exe`.

The optional [pyenv bootstrap](pyenv/Anaconda.bat) downloads the `win-64` Micromamba executable; [conda_far.bat](pyenv/conda_far.bat) is the environment launcher. That launcher calls its sibling `pyenv\msbuild.bat` before Conda activation so the MSVC toolchain and resolved linker are verified first; on success it sets `DISTUTILS_USE_SDK=1` for setuptools. The SQLite harness itself does not install Conda, ICU, Visual Studio or Build Tools.

An x86 ICU build needs **both** an already activated x86 MSVC environment and a separately prepared x86 Conda environment with ICU. An x86 compiler paired with x64 ICU is not sufficient. The same target determines the staged [ICU library and binary directories](#conda-icu-staging) (`lib`/`bin` for x86, `lib64`/`bin64` for x64) and the `/machine:` argument used to generate [SQLite's import library](#exports-and-import-library). To suppress console colors, set `NO_COLOR=1` or `NOCOLOR=1`.

## Build sequence and paths

### Directory layout

The main script's directory is `PROJDIR`. It searches `tool\`, `tools\` and `extra\` in order for `patch_sqlite_misc_autoext.tcl`; the first matching directory becomes `TOOLDIR`. Paths below are relative to `PROJDIR`.

| Location | What belongs there |
|---|---|
| `tool\` (in the shipped layout) | Harness tools, including the extension patcher and include bundler. This is distinct from SQLite's own `out\sqlite\tool\`. |
| `out\cache\` | Downloaded SQLite and ZLIB archives, the enabled extension C sources, and the FP16 archive if PBLOB is enabled. |
| `out\sqlite\` | Extracted SQLite source tree, including `Makefile.msc`, `ext\misc\` and SQLite's own build tools. |
| `out\sqlite\compat\` | Dependencies prepared for this build: `zlib\`, `icu\`, and `FP16-master\` when enabled. |
| `out\build\` | NMake working directory: generated sources, `jimsh0.exe`, intermediate libraries and build products before packaging. |
| `out\build\tsrc\` | Generated target-source workspace. The harness patches and bundles copies here, not the maintained source files. |
| `out\bin\` | Packaged shell and runtime DLLs. |
| `out\include\`, `out\lib\import\`, `out\lib\static\` | Packaged headers, DLL link artifacts, and static library, respectively. See [Packaged artifacts](#packaged-artifacts) for filenames. |

### Build workflow

| Order | Stage | Main location or result |
|---:|---|---|
| 1 | Create output directories, run preflight, set dependency and SQLite options; dispatch a diagnostic if requested | `out\`, `out\build`, `out\build\tsrc` |
| 2 | Obtain and extract the SQLite snapshot | `out\cache\sqlite.zip` → `out\sqlite` |
| 3 | If ZLIB is enabled, obtain, stage and build it | `out\cache\zlib.tar.gz` → `out\sqlite\compat\zlib` |
| 4 | If ICU is enabled, stage or validate the Conda files | `%CONDA_PREFIX%\Library` → `out\sqlite\compat\icu` |
| 5 | Run `.target_source`, then prepare stock extensions (`SQLITE_EXTRA=1`), then call project hooks (`USE_EXTRAS=1`) | `out\build\tsrc` |
| 6 | Generate exports, run the requested SQLite build, regenerate the import library, then collect available artifacts | `out\build` → `out\bin`, `out\include`, `out\lib` |

### Downloads and cache

| Component | On a cache miss | Cache target |
|---|---|---|
| SQLite | Fetch `https://sqlite.org/src/zip/sqlite.zip` (a source snapshot, not a pinned release). | `out\cache\sqlite.zip` |
| ZLIB | Follow `https://github.com/madler/zlib/releases/latest` and record the effective URL in `out\cache\zlib-release-url.txt`. Check cURL's status and require this repository's `/releases/tag/v<version>` with a dotted numeric version before requesting `/releases/download/v<version>/zlib-<version>.tar.gz`. | `out\cache\zlib.tar.gz` |
| Project extension sources | Each enabled hook downloads its single C file from its project's `main` branch. | `out\cache\SQLiteICUex\src\icuex.c`, `out\cache\SQLitePackedBlob\src\pblob.c`, `out\cache\SQLiteRegexpMatches\src\regexpmatches.c` |
| FP16 (PBLOB only) | Fetch the [FP16](https://github.com/Maratyszcza/FP16) `master` archive. | `out\cache\fp16_master.zip` |

If the target file exists, the download stage returns success without inspecting its contents or contacting the server. For ZLIB this also skips the latest-release lookup. There is no automatic refresh, checksum verification, ETag check or version comparison. See [Reproducing a build](#reproducing-a-build) for what to retain.

#### Network access

A first build fetches the SQLite snapshot from `sqlite.org`. Enabled components may also need `github.com` (ZLIB releases and the FP16 archive), the hosts to which GitHub redirects those downloads, and `raw.githubusercontent.com` (the project C sources). The SQLite harness stages ICU from the active Conda prefix; it does not fetch an ICU release. On a fully cached build none of these downloads requires a network request, but the local tool and ICU environment checks still apply.

#### Download validation and logs

The shared [download_file.bat](download_file.bat) interface is `download_file.bat "NAME" "TARGET" "URL"`. On a miss, it downloads into `<target>.part` using a redirect-following GET with retries, not a separate HEAD request. It requires a successful cURL exit and final HTTP status `200` and rejects `text/html` irrespective of case or media-type parameters before renaming the partial file to the final name. A missing or generic content type is not by itself an error. A leftover `.part` is never a cache hit.

Download progress and errors go to the console on stderr. For SQLite and ZLIB, the response-header chain in `out\cache` is written to `sqlite.log` or `zlib.tar.log`; final status and content type go to `sqlite.zip.response.log` or `zlib.tar.gz.response.log`. These are distinct from the release URL log. The harness removes old `out\stdout.log` and `out\stderr.log` during setup; it does not record a general build transcript in them.

### SQLite extraction

[extract_archive.bat](extract_archive.bat) takes `"NAME" "FLAG" "SRC" "DST"`. `FLAG` is the on-disk path of a file or directory supplied by the archive. Paths are resolved relative to the caller. After checking that the archive file and destination directory exist, the helper skips extraction if `FLAG` exists. Otherwise it runs `"%TAR%" -x -f "%SRC%" -C "%DST%"` without changing the working directory and returns tar's status. When called independently with `TAR` unset, it uses `%SystemRoot%\System32\tar.exe`.

For SQLite, the flag is `out\sqlite\Makefile.msc`, supplied by `sqlite.zip`. Its presence skips extraction; it does not prove that every other file was extracted.

### ZLIB staging and build

`:ZLIB_EXTRACT` passes the existing `out\sqlite\compat` directory to the extractor. For a new build, it renames the single `zlib-<dotted-numeric-version>` directory containing `win32\Makefile.msc` to `zlib`. Keep unrelated or leftover `zlib-*` directories out of `compat`; the harness will not choose between multiple matches. The rename will not overwrite an existing `zlib` directory.

The extractor requires the cached archive on every run. If `compat\zlib\win32\Makefile.msc` already exists, it skips extraction. If `compat\zlib\zlib1.dll` is absent, the harness invokes `Makefile.msc`'s `zlib` target with `ZLIBLIB=all` from the SQLite source directory; otherwise it reuses the DLL. The collector copies `zlib1.dll` to `out\bin` if it is present.

### Conda ICU staging

Conda is the only ICU source in this harness. The earlier Visual Studio source build produced a small `icudt` stub DLL rather than the full ICU data DLL. Staging the headers, import libraries and data-bearing runtime DLLs from one Conda installation avoids that limitation. The checks below establish file presence, nonzero size and matching runtime names; they do **not** exercise a data-dependent ICU operation.

On first use, `:ICU_CONDA` checks for `%CONDA_PREFIX%\python.exe` and `%CONDA_PREFIX%\Library\bin\icuinfo.exe`. Neither executable is run. It copies one installation into a fresh `out\sqlite\compat\icu.stage`, removes unversioned `icu??.dll` and `icutest*.dll` there, validates the set, writes `.icu-staged`, then renames the directory to `icu`. Compilation, linking and packaging continue to use the established paths:

| Source under `%CONDA_PREFIX%\Library` | Destination under `out\sqlite\compat\icu` for x86 | Destination for x64 |
| ------------------------------------- | ------------------------------------------------- | ------------------- |
| `include\unicode\` (header tree)      | `include\unicode\`                                | `include\unicode\`  |
| `lib\icu??.lib`                       | `lib\`                                            | `lib64\`            |
| `bin\icu*.dll` and `bin\icuinfo.exe`  | `bin\`                                            | `bin64\`            |

A valid set contains exactly one versioned common DLL (`icuuc<digits>.dll`) and these nonempty files:

- Headers: `unicode\utypes.h`, `unicode\ucol.h`, `unicode\uregex.h` and `unicode\ustring.h`.
- Import libraries: `icudt.lib`, `icuuc.lib` and `icuin.lib`.
- Runtime: `icuinfo.exe`, the common DLL, and `icuin<digits>.dll` and `icudt<digits>.dll` with the **same suffix** as the common DLL.

On later runs, the harness requires `.icu-staged` and revalidates the files already staged. It does not fill missing components from the active prefix or refresh them when Conda changes. Only runtime DLLs are collected into `out\bin`; the staged ICU headers, import libraries and `icuinfo.exe` stay in the compatibility tree.

## SQLite build settings and stock extensions

### Makefile settings

`:BUILD_OPTIONS` sets the following `Makefile.msc` variables:

| Setting | Role |
|---|---|
| `SESSION=1` | Enable the SQLite session extension. |
| `RBU=1` | Enable resumable bulk updates. |
| `API_ARMOR=1` | Enable additional SQLite API misuse checks. |
| `SYMBOLS=0` | Do not request debug symbols through this setting. This is separate from generating DLL exports. |

The script does not set `NO_TCL` or `WITHOUT_JIMSH`. It initializes `EXTRA_SRC` to an empty list of source paths. Stock preparation and project hooks extend that list; it is separate from the compiler definitions below.

### SQLite compile-time options

The harness also clears inherited `OPT_XTRA` and builds its own compiler options. The base definitions, in script order, are:

```text
SQLITE_ENABLE_NORMALIZE
SQLITE_ENABLE_FTS4=1
SQLITE_ENABLE_FTS3_PARENTHESIS
SQLITE_ENABLE_FTS3_TOKENIZER
SQLITE_ENABLE_EXPLAIN_COMMENTS=1
SQLITE_ENABLE_OFFSET_SQL_FUNC=1
SQLITE_ENABLE_QPSG
SQLITE_ENABLE_STAT4
SQLITE_DQS=0
SQLITE_LIKE_DOESNT_MATCH_BLOBS
SQLITE_MAX_EXPR_DEPTH=100
SQLITE_MAX_ATTACHED=100
SQLITE_OMIT_DEPRECATED
SQLITE_DEFAULT_FOREIGN_KEYS=1
SQLITE_DEFAULT_SYNCHRONOUS=1
SQLITE_USE_URI=1
SQLITE_SOUNDEX
```

`USE_ICU=1` also adds `SQLITE_ENABLE_ICU_COLLATIONS`. Each enabled extension stage appends its own definitions.

### Target-source initialization

Before staging any extension, `:SQLITE_BUILD_INIT` changes to `out\build` and runs:

```cmd
nmake /nologo "TOP=%SQLITEDIR%" /f "%SQLITE_MAKEFILE%" .target_source
```

Directory setup creates `out\build\tsrc`, but an empty directory is not a prepared source tree. When SQLite's [`.target_source` rule](https://github.com/sqlite/sqlite/blob/915d9c4acea4a9036d1df7dcf9e8bd747ba726c4/Makefile.msc#L1957-L1969) runs, it recreates and populates `tsrc` with the sources and generated files needed for the target. The extension steps work on those copies, after generation and before compilation. Do not maintain edits in `tsrc`.

### Stock SQLite extensions

With `SQLITE_EXTRA=1`, `:EXTRA_SRC_STOCK` selects the following 15 modules from SQLite's `ext\misc`. The corresponding definitions are:

| Sources                                                       | Compile definitions, in the same order                                                                                  |
| ------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `compress.c`, `csv.c`, `decimal.c`, `fuzzer.c`, `noop.c`      | `SQLITE_ENABLE_COMPRESS`, `SQLITE_ENABLE_CSV`, `SQLITE_ENABLE_DECIMAL`, `SQLITE_ENABLE_FUZZER`, `SQLITE_ENABLE_NOOP`    |
| `prefixes.c`, `regexp.c`, `remember.c`, `rot13.c`, `series.c` | `SQLITE_ENABLE_PREFIXES`, `SQLITE_ENABLE_REGEXP`, `SQLITE_ENABLE_REMEMBER`, `SQLITE_ENABLE_ROT`, `SQLITE_ENABLE_SERIES` |
| `sha1.c`, `shathree.c`, `sqlar.c`, `uint.c`, `uuid.c`         | `SQLITE_ENABLE_SHA`, `SQLITE_ENABLE_SHATHREE`, `SQLITE_ENABLE_SQLAR`, `SQLITE_ENABLE_UINT`, `SQLITE_ENABLE_UUID`        |

### How extensions enter the amalgamation

There are two distinct jobs: put the extension's C code in `sqlite3.c`, and arrange for SQLite to call its initializer on each new connection. An entry in `EXTRA_SRC` does the first, not the second.

1. **Copy the inputs into `tsrc`.** The stock stage runs SQLite's `tool\cp.tcl` with `out\build\jimsh0.exe` to copy the selected `ext\misc` sources. Each enabled project hook later copies its own cached C source into the same workspace.
2. **Adapt the initializers and update the dispatcher.** [patch_sqlite_misc_autoext.tcl](tool/patch_sqlite_misc_autoext.tcl) adapts loadable-extension entry points for a core build, or recognizes an existing `sqlite3<Name>Init(sqlite3*)` initializer. It writes `misc_ext_init.c`, preserving earlier registrations when a later hook runs. The generated `sqlite3ExtraAutoExtInit` calls only initializers whose `SQLITE_ENABLE_*` definitions are enabled and stops on the first error.
3. **Bundle local includes.** [bundle_extra_src.tcl](tool/bundle_extra_src.tcl) expands literal includes that resolve to local files in `tsrc`. Bare `sqlite3.h` and `sqlite3ext.h` are not embedded again; ordinary nonlocal includes are left to the compiler. This lets the prepared C files carry their local dependencies into the amalgamation.
4. **Assemble `EXTRA_SRC`.** The stock stage appends its prepared modules and `misc_ext_init.c`, and sets `SQLITE_EXTRA_AUTOEXT=sqlite3ExtraAutoExtInit` in `OPT_XTRA`. Each project hook appends its prepared C file and enables its own definition without replacing earlier entries.
5. **Generate and compile `sqlite3.c`.** `Makefile.msc` passes the ordered `EXTRA_SRC` list to SQLite's amalgamation generator. The extension code becomes part of the same C translation unit as SQLite; for example, RegexpMatches follows and can use the stock `regexp.c` implementation. When an application opens a connection, SQLite invokes the selected dispatcher. No separate extension DLLs or `.load` commands are needed.

For an example of adapting this workflow to another extension, see [SQLiteExtensionTemplate](https://github.com/pchemguy/SQLiteExtensionTemplate). The [SQLite MSVC Build / Amalgamation Integration field note](https://github.com/pchemguy/Field-Notes/tree/main/notes/11-sqlite-msvc-build) discusses the underlying SQLite build mechanisms.

## Project extension hooks

Each of the three shipped hooks runs by default when `USE_EXTRAS=1`. Set an individual switch to `0` to skip that extension and its downloads. The enabled extensions are compiled into SQLite; there are no separate extension DLLs to load.

| Extension                                     | Switch                        | SQL interface and build dependency                                                                                                                                                                                                                                                                        |
| --------------------------------------------- | ----------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [ICUex](sqlite_ext_icuex.bat)                 | `SQLITE_ENABLE_ICUEX`         | Provides the `UTF_CI` and `UTF_CI_AI` collations, `str_casefold()` and `str_normalize()`. Keep `USE_ICU=1` for the Conda ICU headers and libraries.                                                                                                                                                       |
| [PBLOB](sqlite_ext_pblob.bat)                 | `SQLITE_ENABLE_PBLOB`         | `pblob_pack()` and `pblob_unpack()` convert between one-dimensional numeric JSON arrays and binary16 or binary32 floating-point BLOBs. It uses SQLite’s internal JSON routines. The hook copies the headers from `out\sqlite\compat\FP16-master\include` into `out\build\tsrc`; no FP16 library is built. |
| [RegexpMatches](sqlite_ext_regexpmatches.bat) | `SQLITE_ENABLE_REGEXPMATCHES` | `regexp_matches()` and `regexpi_matches()` return successive matches as a JSON array. Keep `SQLITE_EXTRA=1`: the module uses SQLite's JSON internals and must follow the stock `regexp.c` in the amalgamation.                                                                                            |

### FP16 headers for PBLOB

The [PBLOB hook](sqlite_ext_pblob.bat) uses `out\cache\fp16_master.zip`. It extracts the archive under `out\sqlite\compat` unless `FP16-master\` already exists, then copies the contents of `FP16-master\include\` into `out\build\tsrc\` before bundling `pblob.c`. Reusing the extracted directory skips unpacking, not the header copy. There is no separate FP16 library to link or DLL to distribute; disabling PBLOB skips this dependency.

### Post-build registration checks

To check that all three registered in the packaged shell, run this after a full build:

```cmd
out\bin\sqlite3.exe :memory: "SELECT str_casefold('ABC'), typeof(pblob_pack('[1,2]')), regexp_matches('[0-9]+','a12b3');"
```

Expected output: `abc|blob|["12","3"]`.

From the build base, start the packaged shell with `out\bin\sqlite3.exe :memory:`. Run the query for each extension you enabled and compare its rows with the expected results below.

**PBLOB**

```sql
SELECT * FROM pragma_function_list() WHERE name like 'pblob_%' ORDER BY name, narg;
```

| name         | builtin | type | enc  | narg |   flags |
| ------------ | ------: | ---- | ---- | ---: | ------: |
| pblob_pack   |       0 | s    | utf8 |    1 | 2099200 |
| pblob_pack   |       0 | s    | utf8 |    2 | 2099200 |
| pblob_unpack |       0 | s    | utf8 |    1 | 2099200 |

**ICUex**

```sql
SELECT name FROM pragma_collation_list() WHERE name like 'UTF_%' ORDER BY name;
```

| name      |
| --------- |
| UTF_CI    |
| UTF_CI_AI |

```sql
SELECT * FROM pragma_function_list() WHERE name like 'str\_%' ESCAPE '\' ORDER BY name, narg;
```

| name          | builtin | type | enc  | narg |   flags |
| ------------- | ------: | ---- | ---- | ---: | ------: |
| str_casefold  |       0 | s    | utf8 |    1 | 2099200 |
| str_normalize |       0 | s    | utf8 |    2 | 2099200 |

**RegexpMatches**

```sql
SELECT * FROM pragma_function_list() WHERE name like 'regexp%\_%' ESCAPE '\' ORDER BY name, narg;
```

| name            | builtin | type | enc  | narg |   flags |
| --------------- | ------: | ---- | ---- | ---: | ------: |
| regexp_matches  |       0 | s    | utf8 |    2 | 2099200 |
| regexpi_matches |       0 | s    | utf8 |    2 | 2099200 |

### Adding a hook

To add a project extension, place a batch file named `sqlite_ext_<name>.bat` beside `sqlite_msbuild.bat`. With `USE_EXTRAS=1` (the default), `:EXTRA_SRC_THIRD` calls each file matching `sqlite_ext_*` in that directory, with no arguments. The pattern is not restricted to `.bat`, so keep source files and notes outside that prefix. Use a harness path without spaces for hook discovery: the wildcard in the `for` loop is unquoted.

Hooks run after `out\build\tsrc` is ready and before SQLite is built, even when `SQLITE_EXTRA=0`. Use `%PROJDIR%` for project inputs and `%TSRC%` for prepared sources rather than relying on the current working directory. Append source paths to `EXTRA_SRC` and any compiler definitions to `OPT_XTRA`, preserving values from the stock stage or earlier hooks. Those changes must still be in the caller’s environment when the hook returns. A nonzero exit code stops the build before NMake compiles SQLite.

The shipped hooks update the generated dispatcher, but only `:EXTRA_SRC_STOCK` adds `misc_ext_init.c` to `EXTRA_SRC` and sets `SQLITE_EXTRA_AUTOEXT`. Keep `SQLITE_EXTRA=1` for their built-in registration. With `SQLITE_EXTRA=0`, a custom hook that needs registration must arrange it itself.

## Exports and import library

`:SQLITE_BUILD` works in `out\build`. The definition file and the two `.lib` files have different roles in its four steps:

1. **Build the initial definition target.** The `sqlite3.def` NMake target depends on `libsqlite3.lib`. Passing the configured source list here makes the static library available for symbol inspection:

   ```cmd
   nmake /nologo "EXTRA_SRC=%EXTRA_SRC%" "TOP=%SQLITEDIR%" /f "%SQLITE_MAKEFILE%" sqlite3.def
   ```

2. **Replace `sqlite3.def`.** The harness starts the file with `EXPORTS`, runs `dumpbin /linkermember:2 libsqlite3.lib`, and writes the names that match its filter to `exports.txt`. It appends the sorted names to `sqlite3.def` and removes the temporary list. This derives the DLL export list from the customized build rather than keeping SQLite's original list.
3. **Run the requested build.** The final NMake invocation uses the same prepared sources. Here `%*` is the target or options passed to the main batch file; with no arguments NMake uses its default target:

   ```cmd
   nmake /nologo "EXTRA_SRC=%EXTRA_SRC%" "TOP=%SQLITEDIR%" /f "%SQLITE_MAKEFILE%" %*
   ```

4. **Regenerate the import library.** `lib.exe` uses the replacement definition file and the active MSVC target (`x86` or `x64`). Its output is `sqlite3.lib`, not the static `libsqlite3.lib` inspected in step 2:

   ```cmd
   lib /def:"%BUILDDIR%\sqlite3.def" /out:"%BUILDDIR%\sqlite3.lib" /machine:%VSCMD_ARG_TGT_ARCH%
   ```

The export list is not independently validated, and the temporary list is opened for append. After an interrupted run, do not assume the next `.def` is complete or free of stale entries. For a binary distribution, inspect the actual DLL with `dumpbin /exports out\bin\sqlite3.dll`, then link and run a client against the packaged import library for each target architecture you distribute.

## Packaged artifacts

| Files collected | Destination | Use |
|---|---|---|
| `sqlite3.exe`, `sqlite3.dll` | `out\bin` | Command-line shell and SQLite runtime |
| `zlib1.dll`, `icu*.dll` | `out\bin` | Runtime dependencies when the respective features are enabled |
| `sqlite3*.h` from `out\build` | `out\include` | Generated SQLite headers; project `src\*.h` files are not collected |
| `sqlite3.def`, `sqlite3.lib` | `out\lib\import` | Export definition and import library for linking against `sqlite3.dll` |
| `libsqlite3.lib` | `out\lib\static` | Static SQLite library, not the DLL import library |

**Collection is best effort.** `:COLLECT_BINARIES` clears files directly under `out\bin` before copying available products. It does not clear the include or library directories, so older files can remain there. The collector returns success even if an expected artifact is absent or a copy fails. Exit `0` is **not** a guarantee of a complete or current distribution; check the files required by your consumer. Do not keep unrelated files in `out\bin`.

### Static library vs. import library

Link `out\lib\static\libsqlite3.lib` when SQLite's object code should become part of the client binary. This does not make optional dependencies such as ICU static. Link `out\lib\import\sqlite3.lib` instead when the client should call into `sqlite3.dll` at runtime. The import library is needed by the linker, not the running client; the matching DLL and its enabled runtime dependencies must be available at runtime.

## Recovery and reproducibility

### What is reused?

A cache hit, an extraction flag, and a validated installation skip different work:

| Existing item (relative to the build base) | What it skips | What still happens |
|---|---|---|
| Target file under `out\cache\` (archive or extension C source) | Download; for `zlib.tar.gz`, also the latest-release lookup | The harness still runs preflight. A cache hit does not verify the bytes or invalidate later build products. |
| `out\sqlite\Makefile.msc` | SQLite ZIP extraction | The extractor still requires the source archive and destination directory. Other extracted files are not checked. |
| `out\sqlite\compat\zlib\win32\Makefile.msc` | ZLIB archive extraction | The archive is still required; the harness checks the staged directory layout separately. |
| `out\sqlite\compat\zlib\zlib1.dll` | The ZLIB NMake build | Collection still attempts to copy the DLL if ZLIB is enabled. |
| `out\sqlite\compat\FP16-master\` | FP16 extraction | With PBLOB enabled, the ZIP is still required and the headers are copied into `tsrc`. |
| `out\sqlite\compat\icu\.icu-staged` | Copying a new ICU installation | With ICU enabled, preflight still checks the active prefix, and staging revalidates the files in the existing tree. The marker alone is not enough. |

### Cleaning and rebuilding

`sqlite_msbuild.bat clean` forwards `clean` to the final NMake invocation. It is not a project reset: the download cache, extracted source and staged dependencies are separate from NMake's outputs. Replacing just a cached file does not force regeneration of `tsrc`, `sqlite3.c` or its binaries.

| Situation | Action |
|---|---|
| You need to download a cached file again | Move the existing target file out of the cache, then rerun the build. |
| SQLite extraction was interrupted | Move the incomplete `out\sqlite` tree aside and rerun with the cached ZIP. Otherwise an already extracted `Makefile.msc` will cause extraction to be skipped. The tree also contains staged dependencies. |
| A final ICU or ZLIB tree fails validation | Move the affected `compat\icu` or `compat\zlib` tree aside. Do not manufacture the missing files. |
| ICU staging stopped and left `icu.stage` | Inspect the staging directory and move it aside before retrying. Fresh ICU staging requires a new directory. |
| You need a different architecture, feature configuration, dependency version or clean source snapshot | Start in a separate clean base. Replacing a cached archive alone does not invalidate an already completed extraction or rebuild its dependent artifacts. |

To reset the **same** build completely, move aside that base's generated `out` directory after retaining any artifacts you need. For a **different** architecture, configuration, or dependency installation, use a separate base.

### Reproducing a build

The default inputs are not pinned: a fresh cache can select a different SQLite snapshot, ZLIB release, revision of any project extension (`main`), or FP16 revision (`master`). To reconstruct a build, retain:

- The exact archives and extension C sources with their hashes; record the SQLite check-in, ZLIB release, and extension and FP16 commits.
- The Conda ICU package version, build identifier and target architecture. ICU comes from the active prefix, not the download cache.
- The MSVC toolset, target architecture and build switches, including any individual extension overrides.

Reusing a cache avoids downloading different source bytes; it does not reproduce the toolchain or Conda environment.

### Exit status

Most stages stop on a nonzero status. A dispatched diagnostic returns `100` and ends the build before downloads. Normal completion returns `0`, but [artifact collection](#packaged-artifacts) is best effort: a missing output or failed copy does not necessarily change that status.

## Harness tests

From this `README.md`'s directory in a Windows MSVC developer prompt with Python and pytest available:

```cmd
python -m pytest tests
```

The [cache tests](tests/test_download_cache.py) use a loopback HTTP server. The [staging tests](tests/test_dependency_staging.py) exercise extraction destinations, reuse of extracted files, ZLIB release handling and ICU set validation.

**Preflight coverage limitation:** [test_msbuild_check.py](tests/test_msbuild_check.py) still asserts that the main script calls `msbuild_check.bat` and its fixture invokes that filename. The harness now calls [msbuild.bat](msbuild.bat); the assertion does not match and the fixture does not verify the current helper's activation, linker or ICU machine checks.

Pytest exercises the harness; the [post-build SQL checks](#post-build-registration-checks) exercise the packaged shell. To check the DLL interface for a target architecture, compile a small client that calls `sqlite3_open()` with the packaged header (`out\include\sqlite3.h`), link it against `out\lib\import\sqlite3.lib`, and run it with the matching `out\bin\sqlite3.dll` and its runtime dependencies. A successful shell query does not replace this link-and-run check.

## Summary

Use the packaged build according to how your application consumes SQLite:

- **Shell:** Start `out\bin\sqlite3.exe` and run the [registration checks](#post-build-registration-checks) for the extensions you selected.
- **DLL client:** Compile with the headers in `out\include`, link against `out\lib\import\sqlite3.lib`, and deploy the matching `sqlite3.dll` and its runtime dependencies.
- **Static client:** Link against `out\lib\static\libsqlite3.lib` to incorporate SQLite code directly into the client.
- **Before distribution:** Check that the [required artifacts](#packaged-artifacts) were collected and test the interface the consumer will actually use.
