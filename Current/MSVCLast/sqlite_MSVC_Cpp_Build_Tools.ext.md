---
url: https://chatgpt.com/c/6a786079-f408-83eb-87b1-e0d35b2804a5
---

# SQLite MSVC Build System

## Overview

`sqlite_MSVC_Cpp_Build_Tools.ext.bat` downloads, prepares, builds, and packages a customized SQLite distribution on Windows using the Microsoft Visual C++ toolchain and SQLite's `Makefile.msc` build system.

The build system supports:

* the SQLite command-line shell;
* `sqlite3.dll`;
* a static SQLite library;
* a generated Windows import library;
* generated/public SQLite headers;
* optional ZLIB integration;
* optional ICU support, using a complete Conda ICU distribution by default;
* optional stock SQLite `ext/misc` extensions compiled directly into SQLite;
* additional SQLite compile-time features supplied through `OPT_XTRA`.

The build workflow is rooted at the project directory and places all downloaded, generated, intermediate, and final artifacts under `out/`.

The build script is intended for **MSVC x86 or x64 builds on Windows**.

---

## Requirements

### MSVC environment

Run the script from an initialized Microsoft Visual C++ developer command prompt whose target architecture matches the desired SQLite architecture.

For example:

* x64 Native Tools Command Prompt;
* x86 Native Tools Command Prompt;
* an equivalent shell initialized using Visual Studio's environment setup scripts.

The script verifies the presence of the principal MSVC environment variables:

```text
VisualStudioVersion
VSINSTALLDIR
VCINSTALLDIR
```

It also verifies that the following commands can be located:

```text
cl.exe
nmake.exe
tclsh.exe
```

The active target architecture is obtained from:

```text
VSCMD_ARG_TGT_ARCH
```

The supported practical targets are:

```text
x86
x64
```

---

### Conda

The default ICU integration uses the ICU package installed in the active Conda environment. The script expects `CONDA_PREFIX` to identify the environment and validates these two marker files:

```text
%CONDA_PREFIX%\python.exe
%CONDA_PREFIX%\Library\bin\icuinfo.exe
```

The environment must also contain the ICU distribution beneath `%CONDA_PREFIX%\Library`:

```text
%CONDA_PREFIX%\Library\bin\icu*.dll
%CONDA_PREFIX%\Library\lib\icu??.lib
%CONDA_PREFIX%\Library\include\unicode\*.h
```

The project `pyenv` directory contains the Python/Conda bootstrapping suite. See [Bootstrapping Python Environments on Windows](https://github.com/pchemguy/Field-Notes/tree/main/notes/03-python-env-windows); the note is somewhat outdated. `Anaconda.bat` bootstraps the environment and `conda_far.bat` opens an activated shell.

The batch file does not run Python. The `%CONDA_PREFIX%\python.exe` check confirms that `CONDA_PREFIX` identifies a usable Conda environment. Conda is not required when the retained ICU-from-source provider is explicitly selected.

---

### Required tools

#### `cl.exe`

Microsoft C/C++ compiler.

#### `nmake.exe`

Microsoft Program Maintenance Utility.

SQLite's `Makefile.msc` is driven using `nmake`.

#### `dumpbin.exe`

Used during final export generation to inspect the public symbols contained in:

```text
libsqlite3.lib
```

The resulting symbol set is used to regenerate `sqlite3.def`.

#### `lib.exe`

Used to create the final Windows import library:

```text
sqlite3.lib
```

from the generated:

```text
sqlite3.def
```

#### `msbuild.exe`

Required only when the retained ICU-from-source branch is selected. The default Conda ICU branch does not build ICU.

#### `tclsh.exe`

Required both by SQLite's own build system and by the project's Tcl source-processing tools.

#### `curl.exe`

Used to download:

* SQLite;
* ZLIB;
* ICU release metadata and ICU source when the ICU-from-source branch is selected.

#### Windows `tar.exe`

Archive extraction uses:

```text
%windir%\System32\tar.exe
```

The script deliberately selects the Windows system implementation rather than relying on whichever `tar.exe` might occur first in `PATH`.

---

### Visual Studio installation

Microsoft C++ Build Tools may be installed through either:

* [Visual Studio Build Tools](https://go.microsoft.com/fwlink/?LinkId=691126)
* [Visual Studio / Visual Studio Community](https://visualstudio.microsoft.com/downloads)

The required MSVC C/C++ workload and Windows SDK must be installed.

---

## Tcl Discovery

Tcl is a mandatory build-time dependency.

The script searches for Tcl in this order:

1. `tclsh.exe` available through `PATH`;
2. `%TCL_HOME%\bin\tclsh.exe`;
3. predefined fallback installations.

Current fallback locations include:

```text
%SystemDrive%\dev\TCL
%ProgramFiles%\TCL
C:\dev\TCL
G:\dev\TCL
H:\dev\TCL
```

When Tcl is found outside `PATH`, its `bin` directory is prepended to `PATH`.

The script then defines:

```text
TCL_HOME
TCLSH_CMD
TCLDIR
```

and prints the detected Tcl version.

---

## Invocation

From an initialized MSVC developer command prompt:

```cmd
sqlite_MSVC_Cpp_Build_Tools.ext.bat [NMAKE_TARGET_OR_OPTION ...]
```

Arguments that are not recognized as special diagnostic targets are forwarded to the final SQLite `nmake` invocation.

### Default build

```cmd
sqlite_MSVC_Cpp_Build_Tools.ext.bat
```

Runs the configured default SQLite build.

### Specific SQLite target

```cmd
sqlite_MSVC_Cpp_Build_Tools.ext.bat sqlite3.dll
```

Requests the named `Makefile.msc` target.

### Clean target

```cmd
sqlite_MSVC_Cpp_Build_Tools.ext.bat clean
```

Forwards `clean` to SQLite's `Makefile.msc`.

This is **not** a complete project clean. See [Cleaning and rebuilding](#cleaning-and-rebuilding).

---

## Configuration

Configuration is primarily controlled through environment variables.

Defaults are assigned only when the corresponding variable is not already defined, so values can normally be overridden before invoking the script.

Example:

```cmd
set USE_ICU=0
set SQLITE_EXTRA=0
sqlite_MSVC_Cpp_Build_Tools.ext.bat
```

---

### `USE_ICU`

Controls ICU integration.

Default:

```text
USE_ICU=1
```

When enabled, the build system configures SQLite ICU support and packages the corresponding ICU runtime DLLs. `USE_ICU_CONDA` selects the provider; Conda ICU is the implemented default, while the existing ICU-from-source path remains available as an alternate branch.

The two providers are materially different:

* **Conda ICU (default):** uses the complete headers, import libraries, runtime DLLs, and ICU data supplied under `%CONDA_PREFIX%\Library`.
* **ICU from source (legacy/experimental):** downloads and builds ICU4C with MSBuild. The currently accessible Windows build produces a stub `icudt__.dll` only a few kilobytes in size and therefore lacks the full ICU data required by many ICU facilities.

Copying `icu\source\data\in\icudt__l.dat` next to the stub data DLL does not convert that DLL into a data-bearing build. Attempts to generate the data target separately with `/t:MakeData` have not succeeded in the current workflow. The source branch must consequently be treated as functionally limited, even when compilation and linking succeed.

The following SQLite compile definition is added:

```text
SQLITE_ENABLE_ICU_COLLATIONS
```

Disable ICU with:

```cmd
set USE_ICU=0
```

When `USE_ICU` is not 1, the script also forces `USE_ICU_CONDA=0`.

---

### `USE_ICU_CONDA`

Selects the ICU provider when `USE_ICU=1`.

Default:

```text
USE_ICU_CONDA=1
```

Use the retained source-build branch with:

```cmd
set USE_ICU=1
set USE_ICU_CONDA=0
```

With the default value, the script validates the active Conda environment and stages its complete ICU distribution into the existing compatibility tree. This preserves the paths consumed by all downstream build and packaging steps.

---

### `USE_ZLIB`

Controls ZLIB integration.

Default:

```text
USE_ZLIB=1
```

When enabled, the script:

1. downloads the current ZLIB source archive;
2. extracts it into SQLite's compatibility tree;
3. builds `zlib1.dll` through SQLite's `Makefile.msc`;
4. makes ZLIB available to the SQLite build;
5. copies `zlib1.dll` into `out\bin`.

Disable ZLIB with:

```cmd
set USE_ZLIB=0
```

---

### `SQLITE_EXTRA`

Controls integration of selected **stock SQLite `ext/misc` extensions**.

Default:

```text
SQLITE_EXTRA=1
```

When enabled, `:EXTRA_SRC_STOCK` prepares and incorporates the configured stock extension set.

Disable it with:

```cmd
set SQLITE_EXTRA=0
```

---

## Configuration Matrix

| Variable        | Default | Controls                                             |
| --------------- | ------: | ---------------------------------------------------- |
| `USE_ICU`       |       1 | Enable ICU integration                               |
| `USE_ICU_CONDA` |       1 | Use Conda ICU; `0` selects the retained source build |
| `USE_ZLIB`      |       1 | ZLIB download, build, integration, runtime DLL       |
| `SQLITE_EXTRA`  |       1 | Stock SQLite `ext/misc` integrations                 |

---

## Project and Tool Discovery

The script searches for:

```text
patch_sqlite_misc_autoext.tcl
```

in the following locations relative to the batch file:

```text
<script directory>\
<script directory>\tool\
<script directory>\tools\
<script directory>\extra\
```

The directory containing the Tcl script becomes:

```text
TOOLDIR
```

The project root is then defined as the parent of `TOOLDIR`:

```text
PROJDIR=<TOOLDIR>\..
```

All principal build paths are derived from `PROJDIR`.

The script may change its current working directory during individual stages, so persistent locations are represented using absolute paths.

---

## Directory Layout

The expected project source layout is approximately:

```text
<PROJDIR>\
│
├─ tool\                    or tools\, extra\, etc.
│  ├─ patch_sqlite_misc_autoext.tcl
│  └─ bundle_extra_src.tcl
│
├─ sqlite_MSVC_Cpp_Build_Tools.ext.bat
│
└─ out\
```

The generated `out` hierarchy is:

```text
out\
│
├─ cache\
│  ├─ sqlite.zip
│  ├─ zlib.tar.gz
│  ├─ icu_repo_meta.json
│  └─ icu4c-X-sources.zip
│
├─ sqlite\
│  ├─ Makefile.msc
│  ├─ ext\
│  │  └─ misc\
│  ├─ tool\
│  └─ compat\
│     ├─ zlib\
│     └─ icu\
│        ├─ include\unicode\
│        ├─ lib\ and bin\       (x86)
│        └─ lib64\ and bin64\   (x64)
│
├─ build\
│  └─ ...
│
├─ include\
│
├─ lib\
│  ├─ import\
│  └─ static\
│
├─ bin\
│
├─ stdout.log
└─ stderr.log
```

Each build directory contains SQLite-generated build files and a `tsrc` workspace.

---

## Output Directories

### `out\bin`

Runtime binaries.

May contain:

```text
sqlite3.dll
sqlite3.exe
zlib1.dll
icu*.dll
```

Existing files directly under `out\bin` are deleted before binary collection.

---

### `out\include`

Public/development headers.

The collection stage copies:

```text
<BUILDDIR>\sqlite3*.h
<PROJDIR>\src\*.h
```

into this directory.

---

### `out\lib\import`

Windows dynamic-link import artifacts:

```text
sqlite3.def
sqlite3.lib
```

`sqlite3.lib` is regenerated from the final `sqlite3.def`.

---

### `out\lib\static`

Static SQLite library:

```text
libsqlite3.lib
```

This is the static library generated by SQLite's `Makefile.msc`.

---

## Download Cache

Downloaded source archives and release metadata are stored under:

```text
out\cache
```

The downloader generally reuses an existing target file without contacting the upstream server again.

The script does not currently perform:

* checksum verification;
* ETag validation;
* modification-time validation;
* version comparison;
* automatic cache refresh.

Delete the relevant cache entry to force another download.

---

## Download Sources

### SQLite

Source:

```text
https://sqlite.org/src/zip/sqlite.zip
```

Cached as:

```text
out\cache\sqlite.zip
```

This URL follows SQLite's source repository snapshot rather than a fixed version-numbered release archive.

The build is therefore not inherently reproducible across fresh downloads.

---

### ZLIB

Source:

```text
https://zlib.net/current/zlib.tar.gz
```

Cached as:

```text
out\cache\zlib.tar.gz
```

The URL follows the current ZLIB release.

---

### ICU

This download is used only by the retained ICU-from-source branch. The default Conda ICU branch uses the package already installed in the active environment and does not download ICU source.

Release metadata:

```text
https://api.github.com/repos/unicode-org/icu/releases/latest
```

Cached metadata:

```text
out\cache\icu_repo_meta.json
```

The script searches the release metadata for an ICU4C source ZIP URL and downloads the selected archive as:

```text
out\cache\icu4c-X-sources.zip
```

The local archive name is deliberately stable rather than version-specific.

---

## SQLite Build Configuration

`:BUILD_OPTIONS` sets the following `Makefile.msc` variables:

```text
SESSION=1
RBU=1
API_ARMOR=1
SYMBOLS=0
WITHOUT_JIMSH=1
```

`EXTRA_SRC` is initialized empty and populated later according to the selected extension options.

The script does not currently explicitly set `NO_TCL` in `:BUILD_OPTIONS`.

Tcl is nevertheless required as a build-time dependency because SQLite's source-generation workflow uses Tcl.

---

## SQLite Compile-Time Options

The following definitions are added to `OPT_XTRA`:

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
SQLITE_OMIT_DEPRECATED
SQLITE_DEFAULT_FOREIGN_KEYS=1
SQLITE_DEFAULT_SYNCHRONOUS=1
SQLITE_USE_URI=1
SQLITE_SOUNDEX
```

When ICU is enabled, the following is additionally defined:

```text
SQLITE_ENABLE_ICU_COLLATIONS
```

Additional extension-related definitions are appended by the corresponding source-preparation stages.

---

## Stock SQLite Extensions

When:

```text
SQLITE_EXTRA=1
```

`:EXTRA_SRC_STOCK` integrates selected modules from SQLite's:

```text
ext\misc
```

Current modules:

```text
compress.c
csv.c
decimal.c
fuzzer.c
noop.c
prefixes.c
regexp.c
remember.c
rot13.c
series.c
sha1.c
shathree.c
sqlar.c
uint.c
uuid.c
```

The following definitions are enabled:

```text
SQLITE_EXTRA_AUTOEXT=sqlite3ExtraAutoExtInit
SQLITE_ENABLE_COMPRESS
SQLITE_ENABLE_CSV
SQLITE_ENABLE_DECIMAL
SQLITE_ENABLE_FUZZER
SQLITE_ENABLE_NOOP
SQLITE_ENABLE_PREFIXES
SQLITE_ENABLE_REGEXP
SQLITE_ENABLE_REMEMBER
SQLITE_ENABLE_ROT
SQLITE_ENABLE_SERIES
SQLITE_ENABLE_SHA
SQLITE_ENABLE_SHATHREE
SQLITE_ENABLE_SQLAR
SQLITE_ENABLE_UINT
SQLITE_ENABLE_UUID
```

---

### Stock extension preparation

The processing sequence is:

1. copy the selected source files into `tsrc`;
2. run `patch_sqlite_misc_autoext.tcl`;
3. run `bundle_extra_src.tcl`;
4. append the resulting sources to `EXTRA_SRC`.

`patch_sqlite_misc_autoext.tcl` adapts loadable-extension sources for static integration and creates:

```text
misc_ext_init.c
```

The aggregate initializer is selected through:

```text
SQLITE_EXTRA_AUTOEXT=sqlite3ExtraAutoExtInit
```

`bundle_extra_src.tcl` expands or bundles local source dependencies needed by the prepared translation units.

The resulting `EXTRA_SRC` entries include all configured stock modules plus:

```text
misc_ext_init.c
```

---

## ZLIB Build

When:

```text
USE_ZLIB=1
```

the build performs the following operations.

### Download

```text
out\cache\zlib.tar.gz
```

is downloaded when absent.

### Extract

The archive is extracted beneath:

```text
out\sqlite\compat
```

The extracted versioned directory is renamed to:

```text
out\sqlite\compat\zlib
```

### Build

If:

```text
out\sqlite\compat\zlib\zlib1.dll
```

does not already exist, SQLite's `Makefile.msc` is invoked with its `zlib` target.

The existing `zlib1.dll` is reused otherwise.

### Package

`zlib1.dll` is copied into:

```text
out\bin
```

during artifact collection.

---

## ICU Integration

When:

```text
USE_ICU=1
```

ICU support is prepared through one of two provider branches.

### Conda ICU (default)

The default branch is selected by:

```text
USE_ICU=1
USE_ICU_CONDA=1
```

It reads ICU from the active Conda environment:

| ICU component         | Location                                 |
| --------------------- | ---------------------------------------- |
| Runtime DLLs          | `%CONDA_PREFIX%\Library\bin\icu*.dll`    |
| ICU utility           | `%CONDA_PREFIX%\Library\bin\icuinfo.exe` |
| MSVC import libraries | `%CONDA_PREFIX%\Library\lib\icu??.lib`   |
| Public headers        | `%CONDA_PREFIX%\Library\include\unicode` |

The Conda files are not consumed directly by the SQLite build. `:ICU_CONDA` stages them into the same compatibility-tree locations used by the source provider:

| Staged component               | x64 destination                         | x86 destination             |
| ------------------------------ | --------------------------------------- | --------------------------- |
| Headers                        | `out\sqlite\compat\icu\include\unicode` | same                        |
| Import libraries               | `out\sqlite\compat\icu\lib64`           | `out\sqlite\compat\icu\lib` |
| Runtime DLLs and `icuinfo.exe` | `out\sqlite\compat\icu\bin64`           | `out\sqlite\compat\icu\bin` |

This compatibility staging is intentional. `ICUINCDIR`, `ICULIBDIR`, and `ICUBINDIR` retain the same values for both providers, so SQLite compilation, linking, and final binary collection do not require provider-specific branches.

The staging logic is marker-based:

* headers are copied only when `include\unicode\utypes.h` is absent;
* `icu??.lib` import libraries are copied only when `icudt.lib` is absent;
* `icu*.dll` and `icuinfo.exe` are copied only when the staged `icuinfo.exe` is absent.

After copying the runtime directory, the script removes unversioned `icu??.dll` files and `icutest*.dll`. The versioned runtime DLLs remain and are later copied from the staged `ICUBINDIR` to `out\bin` beside `sqlite3.dll` and `sqlite3.exe`.

This branch is preferred because the Conda package contains the complete ICU runtime and data distribution.

Because both providers share the compatibility tree, changing `USE_ICU_CONDA` does not by itself replace files already staged by the other provider. Remove `out\sqlite\compat\icu` when switching providers or Conda ICU versions.

### ICU from source (retained legacy branch)

The previous source workflow remains available until it is deprecated or fixed. Select it explicitly with:

```cmd
set USE_ICU=1
set USE_ICU_CONDA=0
```

#### Release discovery

The script downloads the latest ICU GitHub release metadata.

The source archive URL is extracted by searching the metadata for the expected ICU4C source ZIP naming pattern.

#### Extract

ICU is extracted under:

```text
out\sqlite\compat\icu
```

The expected solution marker is:

```text
source\allinone\allinone.sln
```

#### Build

ICU is built using:

```text
msbuild source\allinone\allinone.sln
```

with:

```text
Configuration=Release
SkipUWP=true
```

MSBuild stdout and stderr are redirected to:

```text
out\stdout.log
out\stderr.log
```

A preexisting ICU build is reused when the expected `icuinfo.exe` exists.

#### Known data limitation

The currently accessible Visual Studio build completes against stub data. Its `icudt__.dll` is only several kilobytes rather than the several tens of megabytes expected from a complete data-bearing ICU distribution. The full data archive is present in the source tree as:

```text
icu\source\data\in\icudt__l.dat
```

Placing that `.dat` file beside the stub DLL does not make the runtime load it automatically. Separate attempts to invoke the MSBuild `MakeData` target have also been unsuccessful. As a result, the source-built ICU may load and expose APIs while operations requiring real ICU data fail or behave as unavailable. It must not be treated as equivalent to the Conda ICU package.

#### Package

Runtime libraries matching:

```text
icu*.dll
```

are copied into:

```text
out\bin
```

The final collection step is provider-independent: it always copies `icu*.dll` from `ICUBINDIR`. For Conda ICU, that directory contains the staged Conda runtime; for source-built ICU, it contains the build products.

---

## Architecture Handling

The active architecture comes from the initialized MSVC environment:

```text
VSCMD_ARG_TGT_ARCH
```

The intended supported values are:

```text
x86
x64
```

---

### ICU paths

For the default Conda provider, source files are rooted at `%CONDA_PREFIX%\Library`; the Conda directory names do not change between x86 and x64 environments. The script stages those files into `lib64`/`bin64` for an x64 MSVC target and into `lib`/`bin` otherwise. Architecture is determined by the environment's installed packages, not by the Conda path name.

The existing Conda bootstrap does not explicitly select a target architecture. On an x64 Windows host it installs an x64 environment by default. This works for x64 SQLite builds.

An x86 SQLite build requires all three components to target x86:

1. the x86 MSVC developer environment;
2. the x86 Conda installation/environment;
3. the resulting SQLite build.

Visual Studio installs the x86 toolchain alongside the x64 toolchain, so selecting the x86 compiler environment is straightforward. Creating a Windows x86 Conda environment requires a separate or semi-manual architecture-controlled Conda setup; the current bootstrap script does not automate it. Until that support is added, Conda-backed x86 builds are not part of the default workflow.

The script does not inspect the architecture of the Conda binaries. Matching the Conda environment to `VSCMD_ARG_TGT_ARCH` is the caller's responsibility; a mismatch is expected to fail during linking or loading.

For the retained source provider, the existing directory selection remains:

For:

```text
VSCMD_ARG_TGT_ARCH=x64
```

the source build uses:

```text
lib64
bin64
```

For other configured targets, the script currently uses:

```text
lib
bin
```

---

### SQLite import library

The final import library is generated using:

```cmd
lib /def:"%BUILDDIR%\sqlite3.def" ^
    /out:"%BUILDDIR%\sqlite3.lib" ^
    /machine:%VSCMD_ARG_TGT_ARCH%
```

Therefore:

```text
x86 -> /machine:x86
x64 -> /machine:x64
```

The import-library architecture follows the target architecture selected by the MSVC developer environment.

---

## SQLite Target-Source Initialization

Before additional extension sources are staged, the build invokes:

```cmd
nmake ... .target_source
```

from the selected build directory.

This initializes SQLite's generated target-source workspace and creates/populates:

```text
<BUILDDIR>\tsrc
```

The subsequent extension preparation stages operate against this workspace.

---

## SQLite Build and Export Generation

`:SQLITE_BUILD` performs a multi-step build.

### 1. Generate the initial SQLite library and definition target

The script first invokes:

```cmd
nmake ... sqlite3.def
```

with the configured `EXTRA_SRC`.

This causes SQLite's build system to generate the required intermediate library state.

---

### 2. Replace `sqlite3.def`

The generated SQLite definition file is replaced.

The script starts a fresh definition file containing:

```text
EXPORTS
```

It then examines:

```text
libsqlite3.lib
```

using:

```cmd
dumpbin /linkermember:2
```

Public symbols matching the configured pattern are extracted, sorted, and appended to:

```text
sqlite3.def
```

The temporary export-name list is then removed.

---

### 3. Run the requested SQLite build

The script performs the final `nmake` invocation:

```cmd
nmake /nologo ^
    "EXTRA_SRC=%EXTRA_SRC%" ^
    "TOP=%SQLITEDIR%" ^
    /f "%SQLITE_MAKEFILE%" %*
```

Any ordinary arguments passed to `sqlite_MSVC_Cpp_Build_Tools.ext.bat` therefore reach this invocation.

---

### 4. Regenerate `sqlite3.lib`

Finally, the Windows import library is regenerated from the custom definition file:

```cmd
lib /def:"%BUILDDIR%\sqlite3.def" ^
    /out:"%BUILDDIR%\sqlite3.lib" ^
    /machine:%VSCMD_ARG_TGT_ARCH%
```

This is important for test and project-extension builds because the final DLL/import interface can contain symbols contributed by integrated project modules in addition to SQLite's conventional exported C API.

---

## `EXTRA_SRC`

`EXTRA_SRC` is assembled incrementally.

It can contain two distinct classes of sources.

### Stock SQLite modules

Added by:

```text
:EXTRA_SRC_STOCK
```

when:

```text
SQLITE_EXTRA=1
```

---

## Build Workflow

The normal build sequence is:

1. `CORE_ENV`
2. `ICU_OPTIONS`, if ICU is enabled; establish the provider-independent compatibility paths
3. `ZLIB_OPTIONS`
4. `TCL_OPTIONS`
5. `BUILD_OPTIONS`
6. `CHECK_PREREQUISITES`
7. `MAKE_DEBUG`
8. `SQLITE_DOWNLOAD`
9. `SQLITE_EXTRACT`
10. `ZLIB_DOWNLOAD`, if enabled
11. `ZLIB_EXTRACT`, if enabled
12. `ZLIB_BUILD`, if enabled
13. `ICU_CONDA`, when `USE_ICU_CONDA=1`: validate and stage ICU from the active Conda environment
14. `ICU_DOWNLOAD` and `ICU_EXTRACT`, only for the retained source provider
15. `ICU_BUILD`, only for the retained source provider
16. `SQLITE_BUILD_INIT`
17. `EXTRA_SRC_STOCK`, if `SQLITE_EXTRA=1`
18. `SQLITE_BUILD`
19. `COLLECT_BINARIES`

---

## Diagnostic Targets

The first argument is treated specially when it is one of:

```text
env
tcl-env
tcl-test
```

For example:

```cmd
sqlite_MSVC_Cpp_Build_Tools.ext.bat env
```

The selected target is invoked directly against SQLite's `Makefile.msc`.

Normal download, dependency preparation, final build, and packaging stages do not continue afterward.

Because diagnostics are dispatched before SQLite download/extraction, the SQLite source tree must already exist.

### Exit status

The current `:MAKE_DEBUG` implementation explicitly returns:

```text
100
```

after running a diagnostic target.

Consequently the top-level script also terminates with a nonzero status after a diagnostic invocation, including when the underlying `nmake` command itself succeeded.

This behavior is intentional in the current implementation only insofar as it terminates normal processing; callers should not interpret status `100` as an ordinary successful build.

---

## Incremental and Reuse Behavior

The workflow deliberately reuses downloaded files, extracted trees, and built dependencies.

Important markers include:

```text
out\cache\sqlite.zip
out\sqlite\Makefile.msc

out\cache\zlib.tar.gz
out\sqlite\compat\zlib\win32\Makefile.msc
out\sqlite\compat\zlib\zlib1.dll

# ICU staging/build markers:
out\sqlite\compat\icu\include\unicode\utypes.h
out\sqlite\compat\icu\lib64\icudt.lib, for x64
out\sqlite\compat\icu\lib\icudt.lib, otherwise
out\sqlite\compat\icu\bin64\icuinfo.exe, for x64
out\sqlite\compat\icu\bin\icuinfo.exe, otherwise

# Source-provider download/extraction state only:
out\cache\icu_repo_meta.json
out\cache\icu4c-X-sources.zip
out\sqlite\compat\icu\source\allinone\allinone.sln

out\cache\fp16_master.zip
out\sqlite\compat\FP16-master
```

If the expected marker exists, the associated operation may be skipped.

The Conda environment is consulted on each Conda-provider invocation to validate `%CONDA_PREFIX%\python.exe` and `%CONDA_PREFIX%\Library\bin\icuinfo.exe`. The ICU files themselves are copied only when their staged markers are absent. Changing or updating the active Conda environment therefore does **not** automatically refresh an already staged ICU tree.

To restage Conda ICU, remove the relevant staged marker or, preferably, the complete `out\sqlite\compat\icu` tree before rebuilding. Do not leave headers, import libraries, and runtime DLLs from different ICU installations mixed in the staging tree.

To force an operation to rerun, remove its relevant archive, extracted tree, build product, or marker.

---

## Cleaning and Rebuilding

Running:

```cmd
sqlite_MSVC_Cpp_Build_Tools.ext.bat clean
```

only forwards `clean` to SQLite's `Makefile.msc`.

It does not remove all project build state.

The workflow maintains independent state in:

```text
out\cache
out\sqlite
out\build
out\build_test
out\bin
out\include
out\lib
```

For a completely fresh build, remove the appropriate parts of `out`.

For example, deleting the complete:

```text
out
```

directory resets:

* downloaded archives;
* extracted SQLite;
* extracted dependencies;
* dependency builds;
* generated target sources;
* SQLite builds;
* packaged artifacts.

---

## Binary and Header Collection

After a successful SQLite build, `:COLLECT_BINARIES` collects development and runtime artifacts.

The current mapping is approximately:

| Build artifact   | Destination      |
| ---------------- | ---------------- |
| `sqlite3.dll`    | `out\bin`        |
| `sqlite3.exe`    | `out\bin`        |
| `sqlite3.def`    | `out\lib\import` |
| `sqlite3.lib`    | `out\lib\import` |
| `libsqlite3.lib` | `out\lib\static` |
| `sqlite3*.h`     | `out\include`    |
| `icu*.dll`       | `out\bin`        |
| `zlib1.dll`      | `out\bin`        |

Before collection:

```text
out\bin
```

is cleared of existing files.

The include and library directories are not globally cleared.

---

## Static Library vs Import Library

The build produces two distinct `.lib` artifacts.

### `libsqlite3.lib`

Stored under:

```text
out\lib\static
```

This is SQLite's static library.

A consumer linking against it incorporates SQLite code into the consuming binary.

### `sqlite3.lib`

Stored under:

```text
out\lib\import
```

This is the Windows import library corresponding to:

```text
sqlite3.dll
```

It is regenerated from:

```text
sqlite3.def
```

and is used when linking another Windows binary dynamically against the generated SQLite DLL.

---

## Error Handling

The script uses fail-fast stage dispatch.

Most stages are invoked using the pattern:

```cmd
call :STAGE || exit /b !ERRORLEVEL!
```

A nonzero status therefore terminates the normal workflow and propagates the failure code.

Several subroutines use:

```text
SetLocal EnableDelayedExpansion
```

where current `ERRORLEVEL` values must be inspected inside parenthesized command blocks.

Successful normal completion returns:

```text
0
```

---

### Binary collection exception

`:COLLECT_BINARIES` is invoked without a fatal conditional:

```cmd
call :COLLECT_BINARIES
```

The routine uses conditional copy operations and currently returns success explicitly.

Artifact collection failures therefore do not necessarily propagate in the same way as the principal build stages.

---

## Prerequisite Validation Scope

`:CHECK_PREREQUISITES` currently explicitly validates:

```text
VisualStudioVersion
VSINSTALLDIR
VCINSTALLDIR
cl.exe
nmake.exe
tclsh.exe
```

Other tools are required by applicable stages but are not all checked there, including:

```text
curl.exe
dumpbin.exe
lib.exe
msbuild.exe
%windir%\System32\tar.exe
```

The Conda ICU branch additionally requires an active environment with `%CONDA_PREFIX%\python.exe`, `%CONDA_PREFIX%\Library\bin\icuinfo.exe`, and the expected headers, import libraries, and DLLs beneath `%CONDA_PREFIX%\Library`.

`msbuild.exe` is required only for the retained ICU-from-source branch.

---

## Logs

The script initializes:

```text
out\stdout.log
out\stderr.log
```

Existing copies are deleted at the start of each invocation.

ICU MSBuild output is redirected to these files when the source provider is selected. The default Conda provider performs no ICU compilation.

Most other commands continue to emit output directly to the console.

---

## Network Access

A first build may require HTTPS access to:

```text
sqlite.org
zlib.net
api.github.com
github.com
```

The default ICU branch relies on Conda package installation performed by the environment bootstrap. ICU-specific GitHub access is required by the build script only when the source provider is selected.

Once the relevant caches, extracted trees, and dependency builds exist, many subsequent operations can reuse those local artifacts.

---

## Current Implementation Notes

The following details are worth keeping in mind when modifying or automating the build.

### Diagnostic status is nonzero

`:MAKE_DEBUG` returns `100` after running a diagnostic target.

This successfully prevents the normal build from continuing, but also means a diagnostic invocation is not reported as exit status `0`.

### `NO_TCL` is not explicitly configured

The current script sets:

```text
WITHOUT_JIMSH=1
```

but does not explicitly assign `NO_TCL`.

Any `NO_TCL` behavior therefore comes from SQLite's build defaults or a value inherited from the calling environment.

### ICU architecture selection

The default provider takes ICU from the active Conda environment. An x64 Conda environment must be paired with the x64 MSVC target; an x86 Conda environment must be paired with the x86 MSVC target. The current Conda bootstrap implicitly creates x64 environments on x64 hosts and does not yet automate Windows x86 environment creation.

The retained source provider continues to treat `x64` specially and uses unsuffixed `lib`/`bin` directories otherwise.

### Import-library architecture

`sqlite3.lib` generation uses:

```text
/machine:%VSCMD_ARG_TGT_ARCH%
```

so the import library follows the active MSVC target architecture.

---

## Typical Configurations

### Full default build

```cmd
sqlite_MSVC_Cpp_Build_Tools.ext.bat
```

Current defaults enable:

```text
USE_ICU=1
USE_ICU_CONDA=1
USE_ZLIB=1
SQLITE_EXTRA=1
```

ICU is staged from the active Conda environment.

---

### Minimal build

```cmd
set USE_ICU=0
set USE_ICU_CONDA=0
set USE_ZLIB=0
set SQLITE_EXTRA=0

sqlite_MSVC_Cpp_Build_Tools.ext.bat
```

The base `OPT_XTRA` SQLite compile-time configuration remains enabled.

---

## Operational Guidelines

* Run the script from an initialized MSVC command shell.
* For Conda ICU builds, activate the intended Conda environment before invoking the build.
* Keep the MSVC target, Conda package architecture, and SQLite target architecture identical.
* Treat x64 as the default Conda workflow on x64 Windows hosts. Windows x86 Conda setup currently requires manual or semi-manual architecture control.
* Treat `out\cache` as a persistent download cache.
* Delete cached files when deliberately updating upstream dependencies.
* Treat `out\sqlite` as generated/vendor source state rather than project-authored source.
* Do not assume `clean` performs a complete clean.
* Keep stock SQLite extensions separate from project-specific extensions.
* Use `SQLITE_EXTRA=0` for SQLite test configurations where duplicate stock `ext/misc` integration would otherwise occur.
* Prefer the complete Conda ICU distribution. Treat the retained source-built ICU as functionally limited until its data build is fixed.
* Remember that the default upstream URLs are moving targets rather than pinned release inputs.

---

## Summary

`sqlite_MSVC_Cpp_Build_Tools.ext.bat` is the project's Windows/MSVC SQLite distribution builder.

It combines SQLite's native `Makefile.msc` workflow with:

* dependency acquisition;
* optional ICU integration from Conda by default, with a retained source-build branch;
* stock SQLite extension bundling;
* complete symbol-based DLL export generation;
* generation of both static and dynamic-link development artifacts;
* centralized packaging under `out/`.

The resulting `out` tree provides the headers, runtime binaries, static library, and import library required by both SQLite consumers and the project's Python/CFFI testing infrastructure.
