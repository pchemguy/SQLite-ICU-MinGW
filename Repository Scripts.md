---
layout: default
title: Repository scripts
nav_order: 10
permalink: /repo-scripts
---

The project repository contains several scripts for building SQLite and SQLiteODBC. The *Current* folder holds maintained versions, while toolset-specific folders *MinGW* and *MSVC* have drafts, experimental shell scripts, and earlier versions, which may no longer be updated.

### MSVC - SQLite

The main MSVC SQLite script, [sqlite_MSVC_Cpp_Build_Tools.ext.bat][], should be executed from an MSVC shell. It can [build an STDCALL][STDCALL] version of SQLite for use with VBA-x32.  

This script contains three major parts, *DISPATCHER*, *MAIN*, and *TASKS*. *DISPATCHER* is the first and smallest section. It checks if help is requested and, if yes, calls the appropriate task subroutine. Otherwise, it passes control to the beginning of the second *MAIN* section. The *MAIN* section is mostly a sequence of calls to routines in the *TASKS* section. The last *TASKS* section is a collection of small subroutines handling various more or less independent build tasks.

### MSYS2/MinGW - SQLite

The main MSYS2/MinGW SQLite script is [sqlite3.ref.MinGW.Proxy.ext.sh][]. This Bash script has an organization similar to that of the MSVC script. The *main* routine at the end of the file replaces the *MAIN* section, and separate routines perform various build tasks. However, some routines from this Bash script absorb functionality equivalent to several sections from the MSVC script.

### Supporting tools

Integration of loadable extensions requires a fair amount of patching, though I do not use the standard patching routine. The limitations of the Windows build environment largely dictated the choice of an alternative solution. While the standard Windows command shell is quite limited, the more powerful PowerShell appears to be unreliable junk (probably due to Microsoft's "great" idea, [AMSI][]). I tried to use PS, but it hung so frequently that I did not want to waste more time fighting it. Since the SQLite build process requires TCL, I switched to it instead. As a bonus, these scripts are toolchain-independent and mostly needed for toolchain-independent operations.

The repository folder *Current/extra* contains four TCL scripts:

  - *addlines.tcl* adds multiple lines from a "patch" file after the unique line in the target file matching the first line in the "patch" file;
  - *replace.tcl* performs literal text replacement tool for the MSVC script (the Bash script uses _sed_ instead);
  - *commentinclude.tcl* comments out C "#include" directive for use by the MSVC script (currently unused);
  - *expandinclude.tcl* replaces the C "#include" with the contents of the included file (currently unused).

The two subfolders of the *Current/extra* folder contain "patch" files processed via the *addlines.tcl* script.

### MSYS2/MinGW - SQLiteODBC

[SQLiteODBC][SQLiteODBC GH] folder contains modified source files used to build the SQLiteODBC driver. Further details are available on a dedicated [page][SQLiteODBC docs].

---

### MinGW folder

NOTE: this folder contains not updated and experimental scripts. They may work but, in general, should not be used.

[sqlite3.ref.sh][Proxy] relies on the stock makefile. It downloads the current SQLite release, unpacks it, configures, patches several source files, sets additional options, runs SQLite’s makefile,  and, finally, copies the library and its dependencies into the bin folder.

[sqlite3.ref.sh/sqlite3.ref.mk][Combo] pair uses a similar bash script, but a simplified makefile is used instead of the stock file. The shell script still runs the *configure* script, but "sqlite3.ref.mk" is copied to the "build" folder and executed instead of SQLite's Makefile.

[sqlite3-MinGW.bat][] is executed from the standard Windows shell. While it should compile SQLite, it has several issues, such as the hardcoded MinGW path, and should be considered a working draft. Noteworthy, the script optionally enables the SQLLOG extension.

The [ICU][] folder contains experimental scripts for building ICU4C-68. While I managed to build ICU, this was a limited exploration. An attempt to link SQLite and ICU statically was partially successful (see the [SQLite-ICU - Partially Static][] folder for the code). Similarly, [SpatialLite][] has a draft that does not actually do anything. I am not providing any further information on these scripts.

<!-- References -->

[MinGW Scripts]: https://github.com/pchemguy/SQLite-ICU-MinGW/tree/master/MinGW
[MSVC Scripts]: https://github.com/pchemguy/SQLite-ICU-MinGW/tree/master/MSVC
[MSYS2/MinGW]: https://www.msys2.org/
[MSVC]: https://docs.microsoft.com/en-us/cpp/build/building-on-the-command-line
[Dev Env]: https://pchemguy.github.io/SQLite-ICU-MinGW/devenv
[Proxy]: https://github.com/pchemguy/SQLite-ICU-MinGW/blob/master/MinGW/Proxy/sqlite3.ref.sh
[Combo]: https://github.com/pchemguy/SQLite-ICU-MinGW/tree/master/MinGW/Independent
[sqlite_MSVC_Cpp_Build_Tools.ext.bat]: https://github.com/pchemguy/SQLite-ICU-MinGW/blob/master/Current/sqlite_MSVC_Cpp_Build_Tools.ext.bat
[sqlite3.ref.MinGW.Proxy.ext.sh]: https://github.com/pchemguy/SQLite-ICU-MinGW/blob/master/Current/sqlite3.ref.MinGW.Proxy.ext.sh
[STDCALL]: https://pchemguy.github.io/SQLite-ICU-MinGW/stdcall
[sqlite3-MinGW.bat]: https://github.com/pchemguy/SQLite-ICU-MinGW/blob/master/MinGW/Basic/sqlite3-MinGW.bat
[SQLiteODBC GH]: https://github.com/pchemguy/SQLite-ICU-MinGW/tree/master/Current/SQLiteODBC/Build%20Scripts
[SQLiteODBC docs]: https://pchemguy.github.io/SQLite-ICU-MinGW/odbc
[ICU]: https://github.com/pchemguy/SQLite-ICU-MinGW/tree/master/MinGW/ICU
[SpatialLite]: https://github.com/pchemguy/SQLite-ICU-MinGW/tree/master/MinGW/SpatialLite
[SQLite-ICU - Partially Static]: https://github.com/pchemguy/SQLite-ICU-MinGW/tree/master/MinGW/SQLite-ICU%20-%20Partially%20Static
[AMSI]: https://docs.microsoft.com/en-us/windows/win32/amsi/antimalware-scan-interface-portal
