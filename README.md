
## How to Compile SQLite with ICU on Windows with MinGW

### Overview

[SQLite][SQLite] is arguably the most used database engine worldwide, characterized by especially compact size and modular design. By design, the essential functions form the engine core, with other features developed as extensions. Since extensions provide widely used functions, most of them are available as a part of source code distributions. Select extensions are also enabled in the official [precompiled binaries][SQLite Distros] available for various platforms.

A notable extension not included in the official SQLite binaries or [documentation][SQLite Docs] is [ICU][ICU]. It enables case insensitive string treatment and case conversion for non-ASCII Unicode symbols, whereas the core provides such functions for the Latin alphabet only. The official website has brief SQLite building instructions ([here][How To Compile SQLite], [here][Compile-time Options], and [here][README.md]) but no information on how to enable the ICU extension. Since figuring out the necessary steps was not straightforward because of several obscure issues, I share and discuss scripts that automate the entire process. I also give instructions for setting up [MSYS2/MinGW][MSYS2] toolchain from scratch.

### Development Environment

This tutorial relies on MSYS2/MinGW development environment. MSYS2 provides three mutually incompatible toolchains (MSYS2, MinGW x32, and MinGW x64), and any accidental mixing will likely fail the building process. More toolchains are available (see MSYS2 [package groups][MSYS2 Groups]), but for native compilation on a Windows x64 system, just two base toolchains (x32 and x64) are sufficient. The official x64 installer for a minimum MSYS2 environment can be downloaded from the [front page][MSYS2] or [directly][MSYS2 Setup x64].

Let us assume that the “msys64” folder ([e.g.](e.g.), “B:\dev\msys64”) contains MSYS2x64, and the “msys2pkgs” folder ([e.g.](e.g.), “B:\dev\msys2pkgs”) has cached packages. (While MSYS2 integrates with [ConEmu][ConEmu], this customization is beyond the scope of this tutorial.) [Pacman][MSYS2 Pacman] package manager is available for interactive or script-based package management from the MSYS2 shell (msys64\msys2.exe).

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

Both MinGWx32 and MinGWx64 environments now have the same set of tools installed. In principle, the same workflow, commands, and scripts should work with either toolchain, yielding x32 and x64 applications. The active toolchain is selected based on the environment settings applied by the proper launcher (msys64/mingw32.exe or msys64/mingw64.exe).

In addition to these toolchains, there are several useful tools for checking library dependencies:
 - [Dependency Walker] is a powerful tool. Unfortunately, its development stopped a long time ago, resulting in a significant amount of "noise".
 - [Dependencies] partially replicates the functionality of Dependency Walker, while fixing the "noise" problem.
 - [Far Manager] with [ImpEx - PE & Resource browser] plugin is my favorite option.

I have also used [ShellCheck] to check shell scripts.

### SQLite Source Code

Four different variants of SQLite source code are available from the [downloads][SQLite Distros] and [repository readme][README.md] pages. The variant incorporating a snapshot of the SQLite source tree is the "master" distribution. It includes all individual source files for the engine core and extensions. Individual extensions can be built independently from their source files and loaded at runtime. The "master" snapshot can be used to generate other source code variants. The so-called "amalgamation" is a single combined C source code file. This file incorporates both the engine core and most of the extensions (both C and header files) and yields a single integrated library file. While the simplest way to compile SQLite is probably using the "amalgamation" source code as described on the official [how-to][How To Compile SQLite] page, the "master" release is more convenient for custom building, and it also provides additional insights. Thus, for this tutorial, the ["master" release][SQLite Source Release] will be used.

Start MinGW shell and issue commands:

```bash
#!/bin/bash

cd /tmp
SQLite_URL="https://www.sqlite.org/src/tarball/sqlite.tar.gz?r=release"
wget -c "${SQLite_URL}" --no-check-certificate -O sqlite.tar.gz
tar xzf ./sqlite.tar.gz
mv ./sqlite sqlite3
```

The source folder (./sqlite3) contains three make files:
- "Makefile&#46;in" is a template used by the configure/make GNU toolchain;
- "main&#46;mk" is a GNU make script designed to be called from a parent make file that assigns toolchain variables;
- "Makefile.msc" is used by the Microsoft nmake.

When I started digging into the SQLite build process on Windows, I was particularly interested in two features: enabling the ICU extension and enabling the "[__stdcall][Stdcall]" (see also [Calling convention]). The Microsoft nmake script supports both features (see the source), though I have not tried it myself. The GNU make scripts compatible with MSYS2/MinGW toolchain but primarily targeting non-Windows systems support neither feature.

### Default Build

Let us create "sqlite3/build" subfolder and attempt to run a default build:

```bash
#!/bin/bash

cd /tmp/sqlite3
mkdir -p build && cd ./build
../configure
make -j4
```

Configure should create "Makefile" and five other files in the "build" folder and exit successfully. `make` should generate additional files/folders but should fail. The error message should contain references to files in /usr/include. But /usr/include files belong to the MSYS toolchain, so MinGW and MSYS toolchains have been mixed. `make` should only use files located inside ${MINGW_PREFIX} and its subfolders. Inspection of the compiler's command line should reveal "-I/usr/include" option.

The “sqlite3/build/Makefile” should be inspected next, and it provides a hint that configure script generated this option for the TCL library (compare with “sqlite3/Makefile.in”). TCL is used extensively by the SQLite build process for preprocessing of the source files. The make script also builds a TCL-SQLite interface. To find TCL-related compiler options, the configure script looks for the “tclsh” file and checks for several versioned variants first. Note that MSYS/MinGW setup described above installs TCL is in all toolchains. The “tclsh” file from the MSYS package has a version suffix, whereas the one from the MinGW package does not. Because both MinGW and MSYS binary directories are in the path, configure picks the wrong TCL package. Also, note that “\$(READLINE_FLAGS)” in the “sqlite3/build/Makefile” points to the MSYS toolchain. The SQLite configure script has options:

- "--with-tcl=DIR" - directory containing tcl configuration (tclConfig&#46;sh);
- "--with-readline-lib" - specify readline library;
- "--with-readline-inc" - specify readline include paths.

It turns out that “\$(READLINE_FLAGS)” does not affect the build process, and we will fix it in the final script. Let us add the “--with-tcl=${MINGW_PREFIX}/lib” configure option only and run configure/Makefile again. “make” should fail with a “libtool” error message about library linking. According to information available from the Internet, “libtool” has a bug. To skip the problematic code section, “configure” should be executed as follows:

```bash
lt_cv_deplibs_check_method="pass_all" ../configure "--with-tcl=${MINGW_PREFIX}/lib
```

and "make" should now succeed.
 
### ICU-Enabled Build

In order to compile SQLite with ICU exetnsions enabled, the following needs to be done:

- `-DSQLITE_ENABLE_ICU` option must be supplied to the compiler;
- `-I` flags pointing to the ICU include directories needs to be supplied to the compiler;
- `-l` and `-L` flags specifying names and locations of the necessary libraries needs to be supplied to the linker.
 
An important consideration regarding the linker flags is that *the order of these flags matters when static compilation is requested*. The safe attitude is to assume that these flags always need to be supplied in the correct order. In the command line, dependencies should follow the module depending on it (*including the source/object files*). The necessary flags can be obtained via pkg-config or icu-config (though the two methods yield slightly different sets):

```bash
# via icu-config
ICU_CFLAGS="$(icu-config --cflags --cppflags)"
ICU_LDFLAGS="$(icu-config --ldflags --ldflags-system)"

via pkg-config 
ICU_CFLAGS="$(pkg-config --cflags icu-i18n)"
ICU_LDFLAGS="$(pkg-config --libs --static icu-i18n)"
```

These flags then need to be injected into the commands executed by the SQLite Makefile. Rather than manually editing the generated Makefile, we should go over the provided [shell script][SQLite Build Proxy Script].

1. Downlad the source
This routine checks if SQLite archive is present. If not, SQLite source is downloaded. If the “configure” script does not exist, it unpacks the archive and renames the folder to “sqlite3”.

```bash
get_sqlite() {
  cd "${BASEDIR}" || ( echo "Cannot enter ${BASEDIR}" && exit 101 )
  local SQLite_URL="https://www.sqlite.org/src/tarball/sqlite.tar.gz?r=release"
  if [[ ! -f ./sqlite.tar.gz ]]; then
    echo "____________________________________________"
    echo "Downloading the current release of SQLite..."
    echo "--------------------------------------------"
    wget -c "${SQLite_URL}" --no-check-certificate -O sqlite.tar.gz \
      || EC=$?
    (( EC != 0 )) && echo "Error downloading SQLite ${EC}." && exit 102
  else
    echo "________________________________________________"
    echo "Using previously downloaded archive of SQLite..."
    echo "------------------------------------------------"
  fi

  if [[ ! -f "./${DBDIR}/configure" ]]; then
    tar xzf ./sqlite.tar.gz
    mv ./sqlite "${DBDIR}"
  fi
  return 0
}
```

2. Configure
This routine creates a “build” subfolder inside the source folder. If “Makefile” is present in the “build” folder, configure is not run. `readline` flags are obtained via “pkg-config” as full Windows paths. The `$(cygpath -m /)` command returns the Windows path to the MSYS2 root folder, and this prefix is removed from the previously saved flags. Additional options to “configure” enable certain extensions, and “libtool” “lt_cv_deplibs_check_method” is set as a workaround.

```bash
configure_sqlite() {
  mkdir -p "./${BUILDDIR}"
  cd "${BASEDIR}/${BUILDDIR}" \
    || ( echo "Cannot enter ./${BUILDDIR}" && exit 104 )

  if [[ ! -f ./Makefile ]]; then
    [[ ! -r ../configure ]] && echo "Error accessing SQLite configure" \
      && exit 105
    echo "______________________"
    echo "Configuring SQLite3..."
    echo "----------------------"

    local msys_root
    msys_root="$(cygpath -m /)"
    msys_root="${msys_root%/}"
    local readline_inc
    readline_inc=$(pkg-config --cflags --static readline)
    readline_inc=${readline_inc//${msys_root}/}
    local readline_lib
    readline_lib=$(pkg-config --libs --static readline)
    readline_lib=${readline_lib//${msys_root}/}
    
    local CONFIGURE_OPTS
    CONFIGURE_OPTS=(
      --enable-all
      --enable-fts3
      --enable-memsys5
      --enable-update-limit
      --with-tcl=${MINGW_PREFIX}/lib
      --with-readline-lib="${readline_lib}"
      --with-readline-inc="${readline_inc}"
    )

    lt_cv_deplibs_check_method="pass_all" ../configure ${CONFIGURE_OPTS[@]} \
      || EXITCODE=$?
    (( EXITCODE != 0 )) && echo "Error configuring SQLite" && exit 106
  else
    echo "____________________________________________"
    echo "Makefile found. Skipping configuring SQLite3"
    echo "--------------------------------------------"
  fi
  return 0
}  
```

3. Patch the Makefile
This routine patches the generated SQLite Makefile in the “build” folder, cleaning up the $(TOP) variable and ensuring that the Makefile takes ${CFLAGS}, ${CFLAGS_EXTRAS}, $(OPT_FEATURE_FLAGS), and $(LIBS) variables from the environment.

```bash
patch_sqlite3_makefile() {
  cd "${BASEDIR}/${BUILDDIR}" \
    || ( echo "Cannot enter ./${BUILDDIR}" && exit 108 )
  echo "____________________________"
  echo "Patching SQLite3 Makefile..."
  echo "----------------------------"
  sed -e "s|^TOP = \(.*\)$|TOP = ${BASEDIR}/${DBDIR}|;" \
      -e 's|^CFLAGS =\(.*\)$|CFLAGS :=\1 \${CFLAGS}|;' \
      -e 's|^\(TCC = \${CC} \${CFLAGS}\)\( [^$]\)|\1 \${CFLAGS_EXTRAS}\2|;' \
      -e 's|^OPT_FEATURE_FLAGS =\(.*\)$|OPT_FEATURE_FLAGS :=\1 \$(OPT_FEATURE_FLAGS)|;' \
      -e 's|\(--strip-all.*\$(REAL_LIBOBJ)\)\( \$(LIBS)\)*|\1 \$(LIBS)|;' \
      -i Makefile
  return 0
}
```

4. Set the variables from step 3
This routine sets default library flags, flags for static binding of the standard libraries, ICU flags, enables additional SQLite features and optionally changes the calling convention.

```bash
set_sqlite3_extra_options() {
  DEFAULT_LIBS="-lpthread -lm -ldl"
  LIBOPTS="-static-libgcc -static-libstdc++"
  LIBS+="${LIBOPTS}"
  
  ICU_CFLAGS="$(icu-config --cflags --cppflags)"
  CFLAGS_EXTRAS+="${ICU_CFLAGS}"
  ICU_LDFLAGS="$(icu-config --ldflags --ldflags-system)"
  LIBS+="${ICU_LDFLAGS}"
  local libraries
  IFS=$' \n\t'
    libraries=( ${DEFAULT_LIBS} )
  IFS=$'\n\t'
  local library
  for library in "${libraries[@]}"; do
    if [[ -n "${LIBS##*${library}*}" ]]; then
      LIBS+=" ${library}"
    fi
  done
  
  FEATURES=(
    -D_HAVE_SQLITE_CONFIG_H
    -DSQLITE_DQS=0
    -DSQLITE_LIKE_DOESNT_MATCH_BLOBS
    -DSQLITE_MAX_EXPR_DEPTH=0
    -DSQLITE_OMIT_DEPRECATED
    -DSQLITE_DEFAULT_FOREIGN_KEYS=1
    -DSQLITE_DEFAULT_SYNCHRONOUS=1
    -DSQLITE_ENABLE_COLUMN_METADATA
    -DSQLITE_ENABLE_DBPAGE_VTAB
    -DSQLITE_ENABLE_DBSTAT_VTAB
    -DSQLITE_ENABLE_EXPLAIN_COMMENTS
    -DSQLITE_ENABLE_FTS3
    -DSQLITE_ENABLE_FTS3_PARENTHESIS
    -DSQLITE_ENABLE_FTS3_TOKENIZER
    -DSQLITE_ENABLE_MATH_FUNCTIONS
    -DSQLITE_ENABLE_QPSG
    -DSQLITE_ENABLE_RBU
    -DSQLITE_ENABLE_ICU
    -DSQLITE_ENABLE_STMTVTAB
    -DSQLITE_ENABLE_STAT4
    -DSQLITE_SOUNDEX
    -DNDEBUG
  )
    
  ABI_STDCALL=(
    -DSQLITE_CDECL=__cdecl
    -DSQLITE_APICALL=__stdcall
    -DSQLITE_CALLBACK=__stdcall
    -DSQLITE_SYSAPI=__stdcall
    -DSQLITE_TCLAPI=__cdecl
  )

  if [[ "${ABI:-}" == "STDCALL" ]]; then
    echo "Using Stdcall ABI"
    FEATURES=("${FEATURES[@]}" "${ABI_STDCALL[@]}")
  fi

  SERVER_API="-DSQLITE_API=__declspec(dllexport)"
  CLIENT_API="-DSQLITE_API=__declspec(dllimport)"

  OPT_FEATURE_FLAGS="${FEATURES[@]}"
  
  export CFLAGS_EXTRAS OPT_FEATURE_FLAGS LIBS
  return 0
}
```

5. Run "main" routine
The main routine calls the above subroutines and, in the end, runs the Makefile.

6. Required libraries (specific versions will change when the corresponding packages are updated)

The following general libraries, if not statically linked, may be required:
- libgcc_s_dw2-1.dll
- libstdc++-6.dll
- libwinpthread-1.dll

Required ICU libraries:
- libicudt68.dll
- libicuin68.dll
- libicuuc68.dll

### Alternative Approach

The approach discussed in the previous section is based on a single shell script, which prepares the environment and runs SQLite Makefile. Alternatively, a custom [make][CustomSQLiteMake] script can `include` the SQLite Makefile and run custom recipes. In this case, the associated shell [script][Custom SQLite Make Shell] is responsible for minimum preparation.

<!---
### References
--->

[ICU]: https://icu-project.org

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

[SQLite]: https://sqlite.org
[SQLite Distros]: https://sqlite.org/download.html
[SQLite Docs]: https://sqlite.org/docs.html
[SQLite Source Release]: https://sqlite.org/src/tarball/sqlite.tar.gz?r=release
[How To Compile SQLite]: https://sqlite.org/howtocompile.html
[Compile-time Options]: https://sqlite.org/compile.html
[README.md]: https://sqlite.org/src/doc/trunk/README.md
[Stdcall]: https://docs.microsoft.com/en-us/cpp/cpp/stdcall?view=msvc-160
[Calling convention]: https://en.wikipedia.org/wiki/Calling_convention
[SQLite Build Proxy Script]: https://raw.githubusercontent.com/pchemguy/SQLite-ICU-MinGW/master/MinGW/Proxy/sqlite3.ref.sh
[CustomSQLiteMake]: https://raw.githubusercontent.com/pchemguy/SQLite-ICU-MinGW/master/MinGW/Independent/sqlite3.ref.mk
[Custom SQLite Make Shell]: https://raw.githubusercontent.com/pchemguy/SQLite-ICU-MinGW/master/MinGW/Independent/sqlite3.ref.sh
