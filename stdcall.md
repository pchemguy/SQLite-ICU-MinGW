---
layout: default
title: Compiling SQLite for VBA
nav_order: 7
permalink: /stdcall
---

There are several ways to connect to SQLite from VBA. The simplest way probably is to use the [SQLite ODBC][] driver and connect via the [ADODB][] library. At the same time, the VBA code can call dll routines directly. While the x64 version of the dll should be usable for this purpose [as is][x64 convention], the x32 version must follow the [STDCALL][]/WINAPI [ABI][] calling [convention][calling convention].

The official SQLite binaries follow the CDECL convention, but Windows distribution includes a suitable (at least in theory) SQLite copy, winsqlite3.dll. [Rene Nyffenegger][] published a basic [winsqlite3.dll][] example, illustrating this approach. Alternatively, a C-based dll adapter can translate CDECL to STDCALL, making it possible to use the current official SQLite release. [SQLiteForExcel][] developed a dll adapter for the official SQLite binaries, and its [fork][cSQLiteForExcel] demonstrates a refactored version employing a VBA class.

A third approach relies on a custom-built STDCALL version of the library, and it provides the most flexibility. I could produce a usable STDCALL build using the MinGW toolchain, so I decided to use another SQLite-supported Windows toolchain, MSVC, for this purpose.

The [sqlite_MSVC_Cpp_Build_Tools.bat][SQLite MSVC] script placed in an empty writable directory and executed from an MSVCx32 shell builds a working SQLite x32/STDCALL.  However, I could not load the ICU-enabled SQLite build in VBA6 initially. It turned out that, for some reason, Windows failed to resolve and load ICU dependencies automatically. After I had added the LoadLibrary calls loading individual ICU libraries explicitly in order of dependency (icudtXX.dll, icuucXX.dll, icuinXX.dll, icuioXX.dll, icutuXX.dll, sqlite3.dll), sqlite3.dll loaded successfully. Curiously, when compiled with MinGW, the library loads without any issues, with all dependencies being automatically loaded as expected (a more recently recompiled version has exhibited the same problem, however).

<!-- References -->


[SQLite ODBC]: http://www.ch-werner.de/sqliteodbc/
[ADODB]: https://docs.microsoft.com/en-us/sql/ado/microsoft-activex-data-objects-ado
[x64 convention]: https://en.wikipedia.org/wiki/X86_calling_conventions#Microsoft_x64_calling_convention
[STDCALL]: https://docs.microsoft.com/en-us/cpp/cpp/argument-passing-and-naming-conventions
[ABI]: https://en.wikipedia.org/wiki/Application_binary_interface
[calling convention]: https://en.wikipedia.org/wiki/X86_calling_conventions
[Rene Nyffenegger]: https://renenyffenegger.ch/notes/development/databases/SQLite/VBA/index
[winsqlite3.dll]: https://github.com/ReneNyffenegger/winsqlite3.dll-4-VBA
[SQLiteForExcel]: https://github.com/govert/SQLiteForExcel
[cSQLiteForExcel]: https://github.com/b-gonzalez/SQLiteForExcel
[MinGW]: https://pchemguy.github.io/SQLite-ICU-MinGW/devenv
[SQLite script]: https://github.com/pchemguy/SQLite-ICU-MinGW/blob/master/MinGW/Proxy/sqlite3.ref.sh
[VCppBT]: https://go.microsoft.com/fwlink/?LinkId=691126
[Visual Studio]: https://visualstudio.microsoft.com/downloads
[SQLite MSVC]: https://github.com/pchemguy/SQLite-ICU-MinGW/blob/master/MSVC/sqlite_MSVC_Cpp_Build_Tools.bat
