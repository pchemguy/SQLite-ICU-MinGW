---
layout: default
title: Introduction
nav_order: 2
permalink: /introduction
---

[SQLite][] is arguably the most used database engine worldwide, characterized by especially compact size and modular design. By design, the essential functions form the engine core, with other features developed as extensions. Since extensions provide widely used functions, most of them are available as a part of source code distributions. Select extensions are also enabled in the official [precompiled][SQLite Distros] binaries available for various platforms.

A notable extension not included in the official SQLite binaries or [documentation][SQLite Docs] is [ICU][]. It enables case insensitive string operations and case conversion for non-ASCII symbols. The official website has brief SQLite building instructions ([here][How To Compile SQLite], [here][Compile-time Options], and [here][README.md]) but no information on enabling the ICU extension. Since figuring out the necessary steps was not straightforward because of several obscure issues, I share and discuss scripts that automate the entire process, starting from toolchain setup.

Christian Werner's [SQLite ODBC driver][] does not activate the ICU extension either. Moreover, the embedded SQLite library has all extensions disabled and is outdated. The binaries include some extensions as loadable modules, but integrated extensions are more convenient. An alternative build, designed to work with the system SQLite library, did not work for me either. Thus, I decided to build the driver from the source.


<!-- References -->

[SQLite]: https://sqlite.org
[SQLite Distros]: https://sqlite.org/download.html
[SQLite Docs]: https://sqlite.org/docs.html

[How To Compile SQLite]: https://sqlite.org/howtocompile.html
[Compile-time Options]: https://sqlite.org/compile.html
[README.md]: https://sqlite.org/src/doc/trunk/README.md

[ICU]: https://icu-project.org
[MSYS2]: https://msys2.org

[SQLite ODBC driver]: http://ch-werner.de/sqliteodbc
[SQLite ODBC GitHub]: https://github.com/softace/sqliteodbc