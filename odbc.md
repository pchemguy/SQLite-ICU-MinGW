---
layout: default
title: SQLite3 ODBC Driver
nav_order: 9
permalink: /odbc
---

The [SQLite ODBC] driver source includes shell and associated GNU make scripts for automated building (mingw(64)-cross-build\.sh and \*.mingw(64)-cross). Under MSYS/MinGW environment, these scripts do not work as is due to several issues. The zlib source URL included in the shell scripts is outdated. The make scripts include hard-coded absolute paths not matching MSYS directory structure, and under MSYS, native MinGW toolchains are preferable for producing x32 and x64 builds. After fixing the URL and removing prefixes and cross-compilation options, I could build the driver. To use the current SQLite library with all its extensions, however, further adjustments were necessary.

An up-to-date amalgamation file can be injected via the shell script [mingw-cross-build_d.sh][] (the original version is included with the driver). This script performs a fair amount of SQLite source code patching and creates a custom SQLite amalgamation with one additional file embedded, which is the only required modification. This additional file is a patched version of shell\.c, having one function renamed to avoid naming collision and renamed entry point. Such a custom amalgamation can be prepared from the current stock amalgamation and the shell\.c file, and one code line is sufficient to inject it into the existing building process. To enable SQLite extensions, however, compile options also need to be adjusted.

I decided to create two simplified scripts (available from [this repository][ODBC scripts]). These scripts, [mingw-build.sh][] and [Makefile.mingw][], control the build process. They incorporate code to build the ODBC driver with embedded SQLite3 library and an NSIS installer only (x32 or x64 based on the active toolchain). All other driver variants, extensions, and build options/variations are not supported.

*mingw-build\.sh* downloads SQLiteODBC sources and the current SQLite source tarball, unpacks them, runs configure, sets ICU-related flags, copies necessary libraries, and runs [Makefile.mingw][] Makefile. "Makefile\.mingw" is adapted from *Makefile\.mingw-cross*, mostly keeping the code relevant for the SQLite3 ODBC driver. It also includes a logging facility showing the actual build command-line options. The Makefile recursively calls SQLite's  Makefile generating a standard SQLite amalgamation and includes *libshell.c*. Then this Makefile uses this custom amalgamation to build the SQLite3 ODBC driver and NSIS installer.

I also modified two other files. [insta.c][] is a modified version of *inst.c*, which copies provided libraries instead of SQLite extensions. [sqliteodbc_w32w64.nsi][] is a simplified NSIS script for building an NSIS installer (compatible with both x32 and x64 variants). 

To build the SQLiteODBC, download all five files from the repo (Makefile.mingw, insta\.c, mingw-build\.sh, minshell\.c, sqliteodbc_w32w64.nsi) and execute the bash script (mingw-build\.sh) from a MinGW shell. When everything is over, created binaries will be in the *bin* folder next to the downloaded files.

<!-- References -->

[SQLite ODBC]: http://www.ch-werner.de/sqliteodbc/
[ODBC scripts]: https://github.com/pchemguy/SQLite-ICU-MinGW/tree/master/MinGW/SQLiteODBC/Build%20Scripts/
[insta.c]: https://github.com/pchemguy/SQLite-ICU-MinGW/blob/master/MinGW/SQLiteODBC/Build%20Scripts/V3/insta.c
[sqliteodbc_w32w64.nsi]: https://github.com/pchemguy/SQLite-ICU-MinGW/blob/master/MinGW/SQLiteODBC/Build%20Scripts/V3/sqliteodbc_w32w64.nsi
[mingw-build.sh]: https://github.com/pchemguy/SQLite-ICU-MinGW/blob/master/MinGW/SQLiteODBC/Build%20Scripts/V3/mingw-build.sh
[Makefile.mingw]: https://github.com/pchemguy/SQLite-ICU-MinGW/blob/master/MinGW/SQLiteODBC/Build%20Scripts/V3/Makefile.mingw
[mingw-cross-build_d.sh]: https://github.com/pchemguy/SQLite-ICU-MinGW/blob/master/MinGW/SQLiteODBC/Debug%20Versions/mingw-cross-build_d.sh
