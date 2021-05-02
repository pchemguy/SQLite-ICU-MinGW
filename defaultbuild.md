---
layout: default
title: Default Build
nav_order: 4
permalink: /defaultbuild
---

Let us create "sqlite3/build" subfolder and attempt to run a default build:

```bash
#!/bin/bash

cd /tmp/sqlite3
mkdir -p build && cd ./build
../configure
make -j4
```
<p> </p>
Configure should create "Makefile" and five other files in the "build" folder and exit successfully. "make" should generate additional files/folders but should fail. The error message should contain references to files in /usr/include. But /usr/include files belong to the MSYS toolchain, so MinGW and MSYS toolchains have been mixed. "make" should only use files located inside ${MINGW_PREFIX} and its subfolders. Inspection of the compiler's command line should reveal "-I/usr/include" option.

The “sqlite3/build/Makefile” should be inspected next, and it provides a hint that configure script generated this option for the TCL library (compare with “sqlite3/Makefile.in”). TCL is used extensively by the SQLite build process for preprocessing of the source files. The make script also builds a TCL-SQLite interface. To find TCL-related compiler options, the configure script looks for the “tclsh” file and checks for several versioned variants first. Note that MSYS/MinGW setup described above installs TCL is in all toolchains. The “tclsh” file from the MSYS package has a version suffix, whereas the one from the MinGW package does not. Because both MinGW and MSYS binary directories are in the path, configure picks the wrong TCL package. Also, note that “\$(READLINE_FLAGS)” in the “sqlite3/build/Makefile” points to the MSYS toolchain. The SQLite configure script has options:

- "--with-tcl=DIR" - directory containing tcl configuration (tclConfig&#46;sh);
- "--with-readline-lib" - specify readline library;
- "--with-readline-inc" - specify readline include paths.

It turns out that “\$(READLINE_FLAGS)” does not affect the build process, and we will fix it in the final script. Let us add the “--with-tcl=${MINGW_PREFIX}/lib” configure option only and run configure/Makefile again. “make” should fail with a “libtool” error message about library linking. According to information available from the Internet, “libtool” has a bug. To skip the problematic code section, “configure” should be executed as follows:

```bash
lt_cv_deplibs_check_method="pass_all" ../configure "--with-tcl=${MINGW_PREFIX}/lib
```
<p> </p>
and "make" should now succeed.
