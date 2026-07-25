# Integrating ordinary `ext/misc` loadable extensions into the amalgamation as auto-extensions

A few years ago, I experimented with a customized SQLite build process for integrating selected ordinary loadable extensions from `ext/misc` directly into the amalgamation and registering them as auto-extensions.

My primary target is the native Windows/MSVC build, although I have also used the same general approach with MinGW/MSYS2.

The original process required patching extension sources such as `ext/misc/csv.c`, patching `main.c`, and modifying parts of the build system, including `Makefile.msc` and `mksqlite3c.tcl`. It worked, but maintaining those changes across SQLite updates was unnecessarily cumbersome.

After revisiting the current source tree and build machinery, it appears that the integration can now be performed without modifying SQLite core sources or build files.

The relevant facilities are:

1. `Makefile.msc` supports adding sources through `EXTRA_SRC`.
2. `mksqlite3c.tcl` incorporates those extra sources into the generated amalgamation.
3. The `sqlite3BuiltinExtensions` registry in `main.c` provides the following hook:

```c
#ifdef SQLITE_EXTRA_AUTOEXT
  SQLITE_EXTRA_AUTOEXT,
#endif
```

Consequently, the build may define:

```text
-DSQLITE_EXTRA_AUTOEXT=sqlite3ExtraAutoExtInit
```

and provide a corresponding initializer through an extra source file.

This reduces the required customization to preparation of the extension sources themselves. The remainder of the integration can be controlled through the build command line. No patch to `main.c`, `Makefile.msc`, or `mksqlite3c.tcl` is required.

A related discussion of `EXTRA_SRC` and amalgamation generation is available here:

https://sqlite.org/forum/info/903f721f3e7c0d25

## Why the extension sources need preparation

`mksqlite3c.tcl` appends extra sources to the amalgamation after the SQLite core source.

An ordinary `ext/misc` loadable extension is generally written for a different compilation model:

* it includes `sqlite3ext.h`;
* it uses `SQLITE_EXTENSION_INIT1` and `SQLITE_EXTENSION_INIT2`;
* it exports an entry point such as `sqlite3_csv_init()`;
* it may include private headers or auxiliary C sources;
* it may also be compiled separately into `shell.c`, creating the possibility of duplicate internal initializer names.

The extension sources therefore need to be adapted before they are passed through `EXTRA_SRC`.

I use two Tcl scripts for this preparation:

1. `patch_sqlite_misc_autoext.tcl`
2. `bundle_extra_src.tcl`

The scripts may operate on copies of the selected extension sources in the build tree. However, this approach slight increases the pipeline. To simplify the pipeline, I currently patch original files under `ext/misc` in the SQLite source checkout. Both approaches can be implemented, however, without any modification of the build files.

## `patch_sqlite_misc_autoext.tcl`

The first script converts ordinary loadable-extension entry points into initializers that can be called from the built-in auto-extension registry.

It performs the following operations for each selected module.

### Conditional public-header setup

The usual loadable-extension prologue:

```c
#include "sqlite3ext.h"
SQLITE_EXTENSION_INIT1
```

is replaced with a conditional form:

```c
#ifndef SQLITE_CORE
  #include "sqlite3ext.h"
  SQLITE_EXTENSION_INIT1
#else
  #include "sqlite3.h"
#endif
```

When the source is incorporated into `sqlite3.c`, the extension uses the core SQLite declarations.

When it is compiled outside the core, the normal loadable-extension API remains available.

### Static initializer conversion

A conventional loadable-extension entry point such as:

```c
int sqlite3_csv_init(
  sqlite3 *db,
  char **pzErrMsg,
  const sqlite3_api_routines *pApi
)
```

is converted into a core-callable initializer:

```c
int sqlite3CsvInit(sqlite3 *db)
```

The script removes the dynamic-loading setup that is no longer applicable inside the amalgamation, including `SQLITE_EXTENSION_INIT2(pApi)`.

The script also recognizes modules that already provide an initializer in the `sqlite3<Name>Init()` form. Such modules can be registered without converting an exported `sqlite3_<name>_init()` entry point.

### Preservation of loadable-extension support

For converted modules, the script appends a non-core wrapper that restores the conventional exported entry point:

```c
#ifndef SQLITE_CORE
#ifdef _WIN32
__declspec(dllexport)
#endif
int sqlite3_csv_init(
  sqlite3 *db,
  char **pzErrMsg,
  const sqlite3_api_routines *pApi
){
  (void)pzErrMsg;
  SQLITE_EXTENSION_INIT2(pApi);
  return sqlite3CsvInit(db);
}
#endif
```

The prepared source can therefore still be built as an ordinary loadable extension.

### Avoiding collisions between `sqlite3.c` and `shell.c`

Some modules may be incorporated into both the SQLite amalgamation and the shell build.

To prevent a non-core copy from defining the same internal initializer as the copy already present in `sqlite3.c`, the script inserts a conditional alias:

```c
#ifndef SQLITE_CORE
# define sqlite3CsvInit sqlite3CsvInit_Standalone
#endif
```

The initializer keeps its normal name when compiled as part of the SQLite core. A separately compiled copy receives a distinct symbol name.

This is relevant because `SQLITE_CORE` is defined while building the SQLite library core, but is not generally defined merely because a source is being compiled into the shell.

### Dispatcher generation

After processing the requested modules, the script generates `misc_ext_init.c`.

For each selected module it emits a guarded declaration such as:

```c
#ifdef SQLITE_ENABLE_CSV
int sqlite3CsvInit(sqlite3*);
#endif
```

It then emits the dispatcher referenced through `SQLITE_EXTRA_AUTOEXT`:

```c
int sqlite3ExtraAutoExtInit(sqlite3 *db){
  int rc = SQLITE_OK;

#ifdef SQLITE_ENABLE_CSV
  if( rc==SQLITE_OK ) rc = sqlite3CsvInit(db);
#endif

#ifdef SQLITE_ENABLE_SERIES
  if( rc==SQLITE_OK ) rc = sqlite3SeriesInit(db);
#endif

  return rc;
}
```

The generated guards follow the `SQLITE_ENABLE_<NAME>` convention. Initializer names are converted as needed; for example:

```text
sqlite3StmtVtabInit
```

is associated with:

```text
SQLITE_ENABLE_STMT_VTAB
```

This allows the same prepared source set to be used with different build-time module selections.

### Idempotence

The patching operation is intended to be idempotent.

Already converted initializers, previously inserted collision aliases, conditional header blocks, and generated wrappers are detected rather than inserted repeatedly. This is useful when the source-preparation stage is invoked unconditionally by a larger build pipeline.

### Usage

The script intentionally requires bare file names, and all files must be in the same directory (the current TCL shell directory set before launching the script). The script writes dispatcher module `misc_ext_init.c` into the same directory. This convention is somewhat arbitrary and, in principle, can be relaxed by modifying the script.

## `bundle_extra_src.tcl`

The second script prepares sources that depend on local headers or auxiliary C files.

Extra sources are inserted into the amalgamation as individual source bodies. A module that still contains local includes such as:

```c
#include "decimal.h"
#include "some_internal_helper.c"
```

cannot necessarily rely on those files being available or suitable for separate inclusion at the point where the extra source is appended.

`bundle_extra_src.tcl` recursively expands such local includes in place.

### Complete include-graph validation

Before changing any file, the script scans the complete reachable local include graph.

During this phase it verifies that:

* each top-level target is a `.c` or `.h` file in the source directory;
* local includes resolve within that source directory;
* an include does not escape the source tree through `..`;
* absolute include paths are not used;
* the local include graph contains no cycles.

No source is rewritten unless the complete graph has first been accepted.

### Dependency-first expansion

The discovered graph is ordered with dependencies before their includers.

Each included file is therefore fully expanded before its contents are substituted into a parent file.

For example:

```text
module.c
  -> module.h
       -> helper.h
```

is rewritten in the order:

```text
helper.h
module.h
module.c
```

When `module.h` is inserted into `module.c`, it already contains the expanded contents of `helper.h`.

### SQLite public headers

Includes of:

```c
#include "sqlite3.h"
#include "sqlite3ext.h"
```

are not traversed.

They are replaced with a no-op comment because the required SQLite declarations have already been supplied by the surrounding amalgamation or by the conditional header setup inserted by the first script.

### Section boundaries

Expanded files are surrounded by amalgamator-style comments:

```c
/************** Begin file helper.h *************************************/
/* contents */
/************** End of helper.h ****************************************/
```

This preserves some visibility into the original source structure when inspecting the generated amalgamation.

### File preservation and replacement

The script preserves each file's existing newline convention and final-newline state.

Files are replaced atomically and are only rewritten when the generated content differs from the existing content.

## Combined source-preparation sequence

For the modules I currently integrate, the preparation process is conceptually:

1. Copy the selected `ext/misc` sources and their local dependencies into the build source directory.
2. Run `patch_sqlite_misc_autoext.tcl` on the selected extension entry-point sources.
3. Add the generated `misc_ext_init.c` to the set of extra amalgamation sources.
4. Run `bundle_extra_src.tcl` on sources that still contain local dependencies.
5. Invoke the normal SQLite build with the relevant `EXTRA_SRC`, `SQLITE_ENABLE_*`, and `SQLITE_EXTRA_AUTOEXT` definitions.

The exact MSVC command-line setup and the ordering of these stages in my build pipeline are described below.

## Build invocation

[Build-pipeline details to be added.]

## Scripts

### `patch_sqlite_misc_autoext.tcl`

[Full script.]

### `bundle_extra_src.tcl`

[Full script.]
