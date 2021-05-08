---
layout: default
title: SQLite3 ODBC Driver
nav_order: 7
permalink: /odbc
---

The SQLite ODBC driver source includes shell and associated GNU make scripts for automated building (mingw(64)-cross-build\.sh and \*.mingw(64)-cross). Under MSYS/MinGW environment, these scripts do not work as is due to several issues. The zlib source URL included in the shell scripts is outdated. The make scripts include hard-coded absolute paths not matching MSYS directory structure, and under MSYS, native MinGW toolchains are preferable for producing x32 and x64 builds. After fixing the URL and removing prefixes and cross-compilation options, I could build the driver. To use the current SQLite library with all its extensions, however, further adjustments were necessary.

The build shell script performs a fair amount of source code patching and creates a custom SQLite amalgamation embedding one additional file, which is the only required modification. This patched "shell.c" file has one function renamed to avoid naming collision and renamed entry point. Such a custom amalgamation can be prepared, and one code line is necessary to inject it into the existing building process ("[mingw-cross-build_d.sh][]"). To better understand it, however, I created two custom scripts and modified two files available from [this repository][ODBC scripts] and my [SQLite ODBC fork][].

"[insta.c][]" is a modified version of "inst.c", which copies provided libraries instead of SQLite extensions. "[sqliteodbc_w32w64.nsi][]" is a simplified NSIS script for building an NSIS installer (compatible with both x32 and x64 variants). The two custom scripts, "[mingw-build.sh][]" and "[Makefile.mingw][]", control the build process. They incorporate code to build the ODBC driver with embedded SQLite3 library and an NSIS installer only (x32 or x64 based on the active toolchain). All other driver variants, extensions, and build options/variations are not supported.

"mingw-build.sh" downloads current SQLite source tarball, unpacks it, runs configure, enables features via the appropriate compilation flags, sets ICU related flags, copies necessary libraries, and runs "Makefile.mingw" Makefile.

"Makefile.mingw" is adapted from "Makefile.mingw-cross", with most of the code not related to the SQLite3 ODBC driver being removed. It also includes a logging facility showing the actual build command-line options. The Makefile "recursively" calls SQLite's  Makefile generating a standard SQLite amalgamation and customizes it. Similarly to "Makefile.mingw-cross", it then uses this custom amalgamation (with embedded "config.h" and patched "shell.c") to build the SQLite3 ODBC driver and NSIS installer.


<!---
### References
--->

[ODBC scripts]: https://github.com/pchemguy/SQLite-ICU-MinGW/tree/master/MinGW/SQLiteODBC/Build%20Scripts/V3
[SQLite ODBC fork]: https://github.com/pchemguy/sqliteodbc
[insta.c]: https://github.com/pchemguy/sqliteodbc/blob/master/insta.c
[sqliteodbc_w32w64.nsi]: https://github.com/pchemguy/sqliteodbc/blob/master/sqliteodbc_w32w64.nsi
[mingw-build.sh]: https://github.com/pchemguy/sqliteodbc/blob/master/mingw-build.sh
[Makefile.mingw]: https://github.com/pchemguy/sqliteodbc/blob/master/Makefile.mingw
[mingw-cross-build_d.sh]: https://github.com/pchemguy/sqliteodbc/blob/master/mingw-cross-build_d.sh