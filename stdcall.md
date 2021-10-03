---
layout: default
title: Compiling SQLite for VBA
nav_order: 6
permalink: /stdcall
---

There are several ways to connect to SQLite from VBA. The simplest way probably is to use the [SQLite ODBC][] driver and connect via the [ADODB][] library. At the same time, the VBA code can call dll routines directly. While the x64 version of the dll should be usable for this purpose [as is][x64 convention], the x32 version must be compiled following the [STDCALL][]/WINAPI [ABI][] calling [convention][calling convention].

The official SQLite binaries follow the CDECL convention, but Windows distribution includes a suitable (at least in theory) SQLite copy, winsqlite3.dll. [Rene Nyffenegger][] published a basic [winsqlite3.dll][] example, illustrating this approach. Alternatively, a C-based dll adapter can translate CDECL to STDCALL, making it possible to use the current official SQLite release. [SQLiteForExcel][] developed a dll adapter for the official SQLite binaries, and its [fork][cSQLiteForExcel] demonstrates a refactored version employing VBA classes.

A third approach relies on a custom-built STDCALL version of the library, and it provides the most flexibility. An updated version of the *MinGW/Proxy/sqlite3.ref.sh* script executed from the MinGW32 shell (set as described [previously][MinGW]):
`MinGW32$ USEAPI=1 ABI=STDCALL ./sqlite3.ref.sh dll`
was supposed to build such a library. While the build process completes successfully with several warnings, the resulting binary is unusable, and I could not fix it. For this reason, I decided to deviate slightly from MinGW and play with the MSVC toolset as well.

Microsoft Visual C++ Build Tools (VCppBT) yields a working STDCALL x32 SQLite library. VCppBT can be installed via a [dedicated installer][VCppBT] or as part of [Visual Studio][] (including the CE version). Either installer provides the ability to choose various optional components. The minimum configuration should include the Build Tools component and an appropriate SDK package. Since SQLite building workflow relies on TCL, it must also be available (its *bin* subfolder containing the *tclsh.exe* executable must be in the path).

The *MSVC\sqlite_MSVC_Cpp_Build_Tools.bat* script should be placed in an empty writable directory and executed from MSVCx32 shell with TCL added to the path, and it builds a working SQLite x32/STDCALL. However, I could not load the ICU-enabled sqlite3.dll library in VBA6 on Excel 2002 x32 initially. It turned out that, for some reason, Windows failed to resolve and load ICU dependencies automatically. After I had added the LoadLibrary calls loading individual ICU libraries explicitly in order of dependency (icudt68.dll, icuuc68.dll, icuin68.dll, icuio68.dll, icutu68.dll, sqlite3.dll), sqlite3.dll loaded successfully.


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
