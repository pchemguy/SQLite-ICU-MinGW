---
layout: default
title: Overview
nav_order: 1
permalink: /
---

This project explores the building process of the SQLite library and the SQLiteODBC driver on Windows with two toolchains: Microsoft Visual C++ Build Tools (MSVC) and MSYS2/MinGW. The particular focus is on the SQLite-specific building workflow and customizing/extending the building process. The project provides several scripts producing custom builds of the SQLite library and the SQLiteODBC driver. These builds incorporate extended SQLite-related functionality, and the scripts can be used as templates and further tailored to specific needs.

### Features

  - **ICU enabled builds**  
    SQLite does not support insensitive string operations of non-Latin characters, which is essential for user-oriented applications. Instead, the ICU extension enables this functionality. ICU is disabled by default, and no ICU-enabled binaries are available from the official website. Enabling the ICU extension on Windows is not a straightforward process, but I could not find any adequate building/usage instruction on the Internet, so I am sharing my recipe.
  - **STDCALL x32 build (MSVC script)**  
    VBA can access the SQLite library directly, but x32 VBA on Windows can only call STDCALL routines. The official SQLite binaries follow the CDECL calling convention and cannot be accessed from VBA-x32 directly. While building an STDCALL version using the MSYS2/MinGW toolset proved to be problematic, the MSVC toolset turned out to be more friendly in this aspect.
  - **Integrated extensions enabled by default**  
    Loadable extensions implement a large portion of SQLite functionality. The SQLite amalgamation incorporates mature extensions but disables most of them by default. Conversely, all scripts provided by this project enable integrated extensions by default.
  - **Extra extensions integrated with the core**  
    SQLite includes a set of extensions providing less widely used features as dynamically loadable modules, while their source is not part of the amalgamation source. I have selected a few of them for further evaluation and integrated the selected extensions into a custom amalgamation, avoiding the need to load them individually and learning the SQLite building process while doing so. Presently, the following sqlite/ext/misc extensions have been integrated: *csv, fileio, normalize, regexp, series, sha, shathree, sqlar, uint, uuid, and zipfile*.
  - **SQLiteODBC driver embedding current SQLite release with all features enabled**  
    The SQLiteODBC driver has not been updated for a while, and it embeds an outdated SQLite release with many features disabled by default. The scripts provided by this project build a custom version of the SQLiteODBC driver with the current SQLite release and all integrated SQLite extensions enabled.
  - **Dependencies together with SQLite binaries**  
    Three SQLite extensions, ICU and Zipfile/SQLAR, require external dependencies (ICU and Zlib). Since I have encountered problems with static linking of Zlib, I linked both ICU and Zlib dynamically. The building scripts, in turn, copy the Zlib and ICU dependencies as necessary into the folder containing built SQLite binaries.
  - **MSVC Build Tools and MSYS2/MinGW shell scripts**  

### Usage

Build x32-STDCALL SQLite DLL with all standard and extra feature enabled:

```batch
MSVC-x32 Path-to-script> sqlite_MSVC_Cpp_Build_Tools.ext.bat dll
```

Build x64 SQLite DLL and SQLite shell (extra features must be disabled when building the shell):

```bash
MinGW-x64 Path-to-script> WITH_EXTRA_EXT=0 ./sqlite3.ref.MinGW.Proxy.ext.sh dll sqlite3.exe
```

or

```batch
MSVC-x64 Path-to-script> set WITH_EXTRA_EXT=0 && sqlite_MSVC_Cpp_Build_Tools.ext.bat dll sqlite3.exe
```

Build SQLiteODBC driver (not configurable):

```batch
MinGW-x32 Path-to-script> ./mingw-build.sh
rem OR
MinGW-x64 Path-to-script> ./mingw-build.sh
```
