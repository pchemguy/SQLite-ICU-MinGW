## Compile SQLite with ICU on Windows with MinGW

### Overview

"[SQLite][SQLite] is the [most used][SQLite Use] database engine in the world." It also has an incredibly small footprint. The compact size is achieved, in part, via a modularized design: the most important functionalities comprise the engine core, whereas other features are developed as extensions. Mature extensions are included as part of the source code distribution alongside the engine core. Additionally, official [precompiled binaries][SQLite Distros] with a subset of all extensions included are also available for a variety of platforms.  

A notable extension not included in the official binaries (at least for Windows) and not even listed in the "Extensions" section of the [official documentation][SQLite Docs] is [ICU][ICU]. This extension is responsible for small but important functionality for string functions. Specifically, case insensitive string treatment, including string case conversion, is supported by the engine core for the Latin alphabet only. The ICU SQLite extension, when available, enables "case awareness" for non-ASCII Unicode symbols. Unfortunately, there is virtually no information on this extension in the [official documentation][SQLite Docs]. While some compilation instructions are provided ([here][How To Compile SQLite], [here][Compile-time Options], and [here][README.md]), no instructions are provided as to how to enable the ICU extension. Based on my own experience, and some googling, this process may not be particularly straightforward. I have had to do some digging and experimenting to figure it out and decided to summarized what I have learned in case it might be helpful to others.

I am a Windows guy, so this tutorial is focused on compiling SQLite with the ICU extension on Windows using MinGW toolchain. I describe the steps I took starting from setting up the development environment, a script that within such environment automates the entire process, as well as a few gotchas.

### Development Environment


### References

[SQLite][SQLite]
[SQLite - Wikipedia][SQLite - Wikipedia]
[RDBMS][RDBMS]
[MSYS2][MSYS2]

[How To Compile SQLite - sqlite.org][How To Compile SQLite]
[Compile-time Options - sqlite.org][Compile-time Options]
[README.md - sqlite.org][README.md]


[SQLite]: https://sqlite.org
[SQLite Use]: https://www.sqlite.org/mostdeployed.html
[SQLite Distros]: https://sqlite.org/download.html
[SQLite Docs]: https://sqlite.org/docs.html

[ICU]: https://icu-project.org

[MSYS2]: https://msys2.org

[How To Compile SQLite]: https://sqlite.org/howtocompile.html
[Compile-time Options]: https://sqlite.org/compile.html
[README.md]: https://sqlite.org/src/doc/trunk/README.md

