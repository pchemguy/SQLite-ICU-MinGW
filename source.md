---
layout: default
title: SQLite Source Code
nav_order: 3
permalink: /source
---

Four different variants of SQLite source code are available from the [downloads][SQLite Distros] and [repository readme][README.md] pages. The variant incorporating a snapshot of the SQLite source tree is the "master" distribution. It includes all individual source files for the engine core and extensions. Individual extensions can be built independently from their source files and loaded at runtime. The "master" snapshot can be used to generate other source code variants. The so-called "amalgamation" is a single combined C source code file. This file incorporates both the engine core and most of the extensions (both C and header files) and yields a single integrated library file. While the simplest way to compile SQLite is probably using the "amalgamation" source code as described on the official [how-to][How To Compile SQLite] page, the "master" release is more convenient for custom building, and it also provides additional insights. Thus, for this tutorial, the ["master" release][SQLite Source Release] will be used.

Start MinGW shell and issue commands:

```bash
#!/bin/bash

cd /tmp
SQLite_URL="https://www.sqlite.org/src/tarball/sqlite.tar.gz?r=release"
wget -c "${SQLite_URL}" --no-check-certificate -O sqlite.tar.gz
tar xzf ./sqlite.tar.gz
```
<p> </p>
The source folder (./sqlite) contains three "make" files:

- "Makefile&#46;in" is a template used by the configure/make GNU toolchain;
- "main&#46;mk" is a GNU Make script designed to be called from a parent make file that assigns toolchain variables;
- "Makefile.msc" is used by the Microsoft nmake.

When I started digging into the SQLite build process on Windows, I was particularly interested in two features: enabling the ICU extension and enabling the "[__stdcall][Stdcall]" (see also [Calling convention][]). The Microsoft nmake script [supports][SQLite STDCALL] both features.The GNU Make script is compatible with MSYS2/MinGW toolchain, but it supports neither feature (patching is necessary to make these features available).


<!-- References -->

[SQLite Distros]: https://sqlite.org/download.html
[README.md]: https://sqlite.org/src/doc/trunk/README.md
[SQLite Source Release]: https://sqlite.org/src/tarball/sqlite.tar.gz?r=release
[How To Compile SQLite]: https://sqlite.org/howtocompile.html
[Stdcall]: https://docs.microsoft.com/en-us/cpp/cpp/stdcall?view=msvc-160
[Calling convention]: https://en.wikipedia.org/wiki/Calling_convention
[SQLite STDCALL]: https://pchemguy.github.io/SQLite-ICU-MinGW/stdcall
