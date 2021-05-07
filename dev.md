---
layout: default
title: Development Environment
nav_order: 2
permalink: /devenv
---

This tutorial relies on MSYS2/MinGW development environment. MSYS2 provides three mutually incompatible toolchains (MSYS2, MinGW x32, and MinGW x64), and any accidental mixing will likely fail the building process. More toolchains are available (see MSYS2 [package groups][MSYS2 Groups]), but for native compilation on a Windows x64 system, just two base toolchains (x32 and x64) are sufficient. The official x64 installer for a minimum MSYS2 environment can be downloaded from the [front page][MSYS2] or [directly][MSYS2 Setup x64].

Let us assume that the “msys64” folder (e.g., “B:\dev\msys64”) contains MSYS2x64, and the “msys2pkgs” folder (e.g., “B:\dev\msys2pkgs”) has cached packages. (While MSYS2 integrates with [ConEmu][ConEmu], this customization is beyond the scope of this tutorial.) [Pacman][MSYS2 Pacman] package manager is available for interactive or script-based package management from the MSYS2 shell (msys64\msys2.exe).

```bash
#!/bin/bash
# While, in principle, after the initial update, the remaining installation
# can be scripted, occasionally glitches occur causing errors and
# necessitating that the same installation command is repeated.

# Update base installation, repeat until nothing is done.
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
<p> </p>
Both MinGWx32 and MinGWx64 environments now have the same set of tools installed. The same workflow, commands, and scripts work with either toolchain, yielding x32 and x64 applications. The active toolchain is selected based on the environment settings applied by the proper launcher (msys64/mingw32.exe or msys64/mingw64.exe).

In addition to these toolchains, there are several useful tools for checking library dependencies:

- [Dependency Walker] is a powerful tool. Unfortunately, its development stopped a long time ago, resulting in a significant amount of "noise".
- [Dependencies] partially replicates the functionality of Dependency Walker, while fixing the "noise" problem.
- [Far Manager] with [ImpEx - PE & Resource browser] plugin is my favorite option.

I have also used [ShellCheck] to check shell scripts.


<!---
### References
--->

[MSYS2]: https://msys2.org
[MSYS2 Groups]: https://packages.msys2.org/group
[MSYS2 Setup x64]: https://repo.msys2.org/distrib/msys2-x86_64-latest.exe
[MSYS2 Pacman]: https://www.msys2.org/docs/package-management
[ConEmu]: https://conemu.github.io/en/CygwinMsysConnector.html

[Dependency Walker]: https://dependencywalker.com
[Dependencies]: https://github.com/lucasg/Dependencies
[Far Manager]: https://farmanager.com/index.php?l=en
[ImpEx - PE & Resource browser]: https://plugring.farmanager.com/plugin.php?pid=790&l=en
[ShellCheck]: https://shellcheck.net
