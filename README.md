## Compile SQLite with ICU on Windows with MinGW

This tutorial focuses on compiling SQLite with the ICU extension on Windows using the [MSYS2/MinGW][MSYS2] toolchain. Here, I provide additional information on the SQLite building process, which I learned from the source code. I also describe my development environment, the scripts (**available from the repository**) that within such an environment automate the entire process, and some pitfalls.

### Overview

"[SQLite][SQLite] is the [most used][SQLite Use] database engine in the world." The engine features a particularly compact size, which is achieved, in part, via a modularized design: the most important functionalities comprise the engine core, with other features developed as extensions. The source code distribution includes the engine core and mature extensions. The official [precompiled binaries][SQLite Distros] featuring select extensions are also available for various platforms.  

A notable extension not included in the official binaries (at least for Windows) and not even listed in the "Extensions" section of the [official documentation][SQLite Docs] is [ICU][ICU]. This extension is responsible for small but important string-related functionality. Specifically, case insensitive string treatment, including string case conversion, is supported by the engine core for the Latin alphabet only. The ICU SQLite extension, when available, enables "case awareness" for non-ASCII Unicode symbols. Unfortunately, there is virtually no information on this extension in the [official documentation][SQLite Docs]. While some compilation instructions are provided ([here][How To Compile SQLite], [here][Compile-time Options], and [here][README.md]), no instructions are provided as to how to enable the ICU extension. Based on my own experience, and some googling, this process may not be particularly straightforward. I have done some digging and experimenting to figure it out and decided to summarize what I have learned in case this how-to might be helpful to others.

### Development Environment

I use [MSYS2/MinGW][MSYS2] as my Windows development environment. MSYS2 provides three base toolchains (MSYS2, MinGW x32, and MinGW x64), which are incompatible and should not be mixed. (Such accidental mixing is the first pitfall.) More toolchains are available (see MSYS2 [package groups][MSYS2 Groups]), but for native compilation on a Windows x64 system, which is the focus of this tutorial, just two base toolchains (x32 and x64) are sufficient. The minimum MSYS2 environment can be installed by the official installer available from the [website][MSYS2] or [directly][MSYS2 Setup x64] (on an x32 system, an [x32 installer][MSYS2 Setup x32] must be used).

Let us assume that [MSYS2x64][MSYS2 Setup x64] is installed in a msys64 folder. The installation folder does not need to be in the root folder of the system drive, but its path should not contain any spaces. MSYS2 provides [pacman][MSYS2 Pacman] package manager for interactive or script-based package management. I further assume that "msys2pkgs" folder located in the same folder as "msys64" is designated as package cache. For example, "B:\dev\msys64" contains MSYS2 and "B:\dev\msys2pkgs" contains cached packages. (While MSYS2 can be, for example, integrated with [ConEmu][ConEmu], this customization is not essential and is beyond the scope of this tutorial.)

An MSYS2 shell (msys64\msys2.exe) can be used for the remaining setup. Start the shell and change the current folder to "msys64". I needed to run the following command twice to fully update the base installation.

```bash
#!/bin/bash
# While, in principle, after the initial update, the remiaining installation
# can be scripted, ocassionally glitches occur causing errors and
# necessitating that the same installation command is repeated.

# Update base installation
pacman --noconfirm -Syuu
pacman --noconfirm -Syuu

# Change directory to MSYS2 root, showing full Windows path
PWD="$(cygpath -m /)"

# Install MSYS2 packages
pkgs=( base-devel msys2-devel compression development libraries bc ed mc pactoys )
pacman --noconfirm --needed -S --cachedir "${PWD}/../msys2pkgs" ${pkgs[@]}

# Install base MinGW x32 and x64 packages
pkgs=( mingw-w64-i686 mingw-w64-x86_64 )
pacman --noconfirm --needed -S --cachedir "${PWD}/../msys2pkgs" ${pkgs[@]}

# Install MinGW x32 (/ming32) and x64 (/ming64) toolchains
pkgs=( toolchain:m clang:m dlfcn:m icu:m nsis:m )
pacboy --noconfirm --needed -S --cachedir "${PWD}/../msys2pkgs" ${pkgs[@]}
```

At this point both MinGWx32 and MinGWx64 have the same set of tools installed and they can be used for native building of x32 and x64 applications respectively. In principle the same workflow/commands/scripts should work with either toolchain. Whether one or the other is activated is based on the environment settings, and the proper settings are most straightforwardly applied by starting the appropriate shell (msys64/mingw32.exe or msys64/mingw64.exe). I needed a x32 version, so I used MinGWx32 shell. While I did not have a chance to test the x64 toolchain yet, everything discussed below should be equally applicable to either of the two toolchains/shells.

In addition to these toolchains, there are several useful tools for checking library dependencies:
 - [Dependency Walker] - It is still useful, though its development stopped a long time ago. As a result, it has a significant amount of "noise".
 - [Dependencies] - Partially replicates the functionality of [Dependency Walker], while fixing the "noise" problem.
 - [Far Manager] with [ImpEx - PE & Resource browser] plugin - my favorite option.

I have also used [ShellCheck] to check shell scripts.

### SQLite - Basic Compilation Options



<!---
### References

[SQLite][SQLite]
[SQLite - Wikipedia][SQLite - Wikipedia]
[RDBMS][RDBMS]
[MSYS2][MSYS2]

[How To Compile SQLite - sqlite.org][How To Compile SQLite]
[Compile-time Options - sqlite.org][Compile-time Options]
[README.md - sqlite.org][README.md]
--->

[SQLite]: https://sqlite.org
[SQLite Use]: https://www.sqlite.org/mostdeployed.html
[SQLite Distros]: https://sqlite.org/download.html
[SQLite Docs]: https://sqlite.org/docs.html

[ICU]: https://icu-project.org

[MSYS2]: https://msys2.org
[MSYS2 Groups]: https://packages.msys2.org/group
[MSYS2 Setup x64]: https://repo.msys2.org/distrib/msys2-x86_64-latest.exe
[MSYS2 Setup x32]: https://repo.msys2.org/distrib/msys2-i686-latest.exe
[MSYS2 Pacman]: https://www.msys2.org/docs/package-management
[ConEmu]: https://conemu.github.io/en/CygwinMsysConnector.html
[Dependency Walker]: https://dependencywalker.com
[Dependencies]: https://github.com/lucasg/Dependencies
[Far Manager]: https://farmanager.com/index.php?l=en
[ImpEx - PE & Resource browser]: https://plugring.farmanager.com/plugin.php?pid=790&l=en
[ShellCheck]: https://shellcheck.net
[How To Compile SQLite]: https://sqlite.org/howtocompile.html
[Compile-time Options]: https://sqlite.org/compile.html
[README.md]: https://sqlite.org/src/doc/trunk/README.md