---
layout: default
title: Repository Scripts
nav_order: 7
permalink: /repo-scripts
---

The project repository contains several scripts for building SQLite and SQLiteODBC in two directories: [MinGW][MinGW Scripts] and [MSVC][MSVC Scripts]. While this project uses [MSYS2/MinGW][] toolsets as the primary development [environment][Dev Env], it also contains one script for the [MSVC][] toolset.

### MSVC script

[sqlite_MSVC_Cpp_Build_Tools.bat][] script is executed from the MSVC-x32 shell and used for building the STDCALL version of SQLite-x32 for use with VBA-x32. Further details are available on a dedicated [page][SQLite MSVC].

### MSYS2/MinGW scripts

[sqlite3.ref.sh][Proxy] relies on the stock makefile. Various parts of the script are discussed in previous pages. The script downloads the current SQLite release, unpacks it, configures, patches several source files, sets additional options, runs SQLite’s makefile,  and, finally, copies the library and its dependencies into the bin folder.

[sqlite3.ref.sh/sqlite3.ref.mk][Combo] pair uses a similar bash script, but a simplified makefile is used instead of the stock file. The shell script still runs the *configure* script, but "sqlite3.ref.mk" is copied to the "build" folder and executed instead of SQLite's Makefile.

[sqlite3-MinGW.bat][] is executed from the standard Windows shell. While it should compile SQLite, it has several issues, such as the hardcoded MinGW path, and should be considered a working draft. Noteworthy, the script optionally enables the SQLLOG extension.

[SQLiteODBC][SQLiteODBC GH] folder contains modified source files used to build the SQLiteODBC driver. Further details are available on a dedicated [page][SQLiteODBC docs].


The [ICU][] folder contains experimental scripts for building ICU4C-68. While I managed to build ICU, this was a limited exploration. An attempt to link SQLite and ICU statically was partially successful (see the [SQLite-ICU - Partially Static][] folder for the code). Similarly, [SpatialLite][] has a draft that does not actually do anything. I am not providing any further information on these scripts.

<!-- References -->

[MinGW Scripts]: https://github.com/pchemguy/SQLite-ICU-MinGW/tree/master/MinGW
[MSVC Scripts]: https://github.com/pchemguy/SQLite-ICU-MinGW/tree/master/MSVC
[MSYS2/MinGW]: https://www.msys2.org/
[MSVC]: https://docs.microsoft.com/en-us/cpp/build/building-on-the-command-line
[Dev Env]: https://pchemguy.github.io/SQLite-ICU-MinGW/devenv
[Proxy]: https://github.com/pchemguy/SQLite-ICU-MinGW/blob/master/MinGW/Proxy/sqlite3.ref.sh
[Combo]: https://github.com/pchemguy/SQLite-ICU-MinGW/tree/master/MinGW/Independent
[sqlite_MSVC_Cpp_Build_Tools.bat]: https://github.com/pchemguy/SQLite-ICU-MinGW/blob/master/MSVC/sqlite_MSVC_Cpp_Build_Tools.bat
[SQLite MSVC]: https://pchemguy.github.io/SQLite-ICU-MinGW/stdcall
[sqlite3-MinGW.bat]: https://github.com/pchemguy/SQLite-ICU-MinGW/blob/master/MinGW/Basic/sqlite3-MinGW.bat
[SQLiteODBC GH]: https://github.com/pchemguy/SQLite-ICU-MinGW/tree/master/MinGW/SQLiteODBC
[SQLiteODBC docs]: https://pchemguy.github.io/SQLite-ICU-MinGW/odbc
[ICU]: https://github.com/pchemguy/SQLite-ICU-MinGW/tree/master/MinGW/ICU
[SpatialLite]: https://github.com/pchemguy/SQLite-ICU-MinGW/tree/master/MinGW/SpatialLite
[SQLite-ICU - Partially Static]: https://github.com/pchemguy/SQLite-ICU-MinGW/tree/master/MinGW/SQLite-ICU%20-%20Partially%20Static
