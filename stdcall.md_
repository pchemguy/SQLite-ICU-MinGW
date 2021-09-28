---
layout: default
title: Compiling SQLite for VBA
nav_order: 6
permalink: /stdcall
---

There are several ways to connect to SQLite from VBA. The simplest way probably is to use the [SQLite ODBC][] driver and connect via the [ADODB][] library. At the same time, VBA code can call dll routines directly if the dll library is compiled following the [STDCALL][]/WINAPI [ABI][] calling [convention][calling convention].

While the official SQLite binaries follow the CDECL convention, Windows distribution includes a suitable SQLite copy, winsqlite3.dll. Alternatively, a C-based dll adapter can translate calling conventions, making it possible to use the current official SQLite release. [Rene Nyffenegger][] published a basic [winsqlite3.dll][] example. [SQLiteForExcel][] developed a dll adapter for the official SQLite binaries, and its [fork][cSQLiteForExcel] demonstrates a refactored version employing VBA classes.

A third approach relies on a custom-built STDCALL version of the library, and it provides the most flexibility. When executed from either MinGW32 or MinGW64 shell (set as described [above][MinGW]), the [script][SQLite script], provided in the project repository, builds VBA compatible x32/x64 SQLite binaries. Command `ABI=STDCALL ./sqlite3.ref.sh` starts the script, selecting the STDCALL convention. The script downloads the current release of SQLite, unpacks it into the *sqlite* subfolder in the script\'s parent folder, configures it, and builds it in *sqlite/build*. Finally, the dll file and required dependencies are copied into *sqlite/build/bin*.



<!-- References -->


[SQLite ODBC]: http://www.ch-werner.de/sqliteodbc/
[ADODB]: https://docs.microsoft.com/en-us/sql/ado/microsoft-activex-data-objects-ado
[STDCALL]: https://docs.microsoft.com/en-us/cpp/cpp/argument-passing-and-naming-conventions
[ABI]: https://en.wikipedia.org/wiki/Application_binary_interface
[calling convention]: https://en.wikipedia.org/wiki/X86_calling_conventions
[Rene Nyffenegger]: https://renenyffenegger.ch/notes/development/databases/SQLite/VBA/index
[winsqlite3.dll]: https://github.com/ReneNyffenegger/winsqlite3.dll-4-VBA
[SQLiteForExcel]: https://github.com/govert/SQLiteForExcel
[cSQLiteForExcel]: https://github.com/b-gonzalez/SQLiteForExcel
[MinGW]: https://pchemguy.github.io/SQLite-ICU-MinGW/devenv
[SQLite script]: https://github.com/pchemguy/SQLite-ICU-MinGW/blob/master/MinGW/Proxy/sqlite3.ref.sh
