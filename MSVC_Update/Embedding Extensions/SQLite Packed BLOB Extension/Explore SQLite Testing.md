---
url: https://chatgpt.com/c/6a643d87-ce3c-83eb-891c-9e217ab8bd60
project: SQLite Extension
---

## 📗 SQLite Testing - Building and Running

> [!NOTE] Prompt
> 
> How to build SQLite for testing (Windows, MSVC) and run tests?

### Prerequisites

Use the **x64 Native Tools Command Prompt for Visual Studio**, not an ordinary `cmd.exe` initialized without the MSVC environment. For a 32-bit build, use the x86 Native Tools prompt instead. SQLite’s current Windows build documentation explicitly requires this environment. ([SQLite][1])

To run the Tcl-based test suite, install:

* MSVC C++ build tools: `cl.exe`, `link.exe`, `nmake.exe`
* Tcl development installation, including:

  * `tclsh.exe` or versioned equivalent
  * Tcl headers
  * Tcl import libraries

SQLite can build `sqlite3.exe` without Tcl, but its principal test targets require Tcl development libraries. ([SQLite][1])

Assuming Tcl is installed under `C:\Tcl`:

```cmd
set "TCLDIR=C:\Tcl"
set "PATH=C:\Tcl\bin;%PATH%"
```

Verify the environment:

```cmd
where cl
where nmake
where tclsh
cl
tclsh <<< "puts [info patchlevel]"
```

The last command uses shell redirection awkwardly on Windows; the simpler reliable check is:

```cmd
tclsh
```

Then enter:

```tcl
puts [info patchlevel]
exit
```

### Recommended source layout

Testing must be performed from a **canonical SQLite source tree**, not merely from the amalgamation download. The canonical tree contains:

* `Makefile.msc`
* `src\`
* `test\`
* `tool\`
* generated-source scripts
* test-only C modules

The `test\*.test` files are Tcl scripts run through the augmented interpreter `testfixture.exe`. ([SQLite][2])

For example:

```text
B:\SQLite\Current\
    sqlite\        canonical source tree
    build-test\    test build directory
```

For the simplest setup, build directly in the source root:

```cmd
cd /d B:\SQLite\Current\sqlite
```

This avoids complications with `Makefile.msc` path variables while establishing the test workflow.

### Basic test build

Clean any prior build products:

```cmd
nmake /f Makefile.msc clean
```

Build the SQLite test harness:

```cmd
nmake /f Makefile.msc TCLDIR=C:\Tcl testfixture.exe
```

The output is `testfixture.exe`, which is a Tcl interpreter augmented with:

* the SQLite Tcl binding;
* internal test commands;
* fault-injection facilities;
* test-only SQLite interfaces;
* additional C modules from `src\test*.c`.

SQLite documents this as the executable used to run individual `test\*.test` scripts. ([SQLite][2])

### Run one test file

Run a test from the source-tree root:

```cmd
testfixture.exe test\main.test
```

Other examples:

```cmd
testfixture.exe test\select1.test
testfixture.exe test\insert.test
testfixture.exe test\fts5simple.test
```

Use the test harness, not ordinary `tclsh.exe`:

```cmd
testfixture.exe test\some_test.test
```

`testfixture.exe` contains commands that ordinary Tcl does not provide.

A successful test normally finishes with a summary resembling:

```text
0 errors out of ... tests
```

### Run the standard test suite

The conventional aggregate target is:

```cmd
nmake /f Makefile.msc TCLDIR=C:\Tcl test
```

This builds the necessary components and runs the main test suite. The exact set of scripts selected by an aggregate target can evolve with SQLite, so `Makefile.msc` in the checked-out revision is authoritative.

For day-to-day extension development, the practical sequence is:

```cmd
nmake /f Makefile.msc TCLDIR=C:\Tcl clean
nmake /f Makefile.msc TCLDIR=C:\Tcl testfixture.exe
testfixture.exe test\your_extension.test
nmake /f Makefile.msc TCLDIR=C:\Tcl test
```

### Development test suite

SQLite exposes a `devtest` target specifically for development testing:

```cmd
nmake /f Makefile.msc TCLDIR=C:\Tcl devtest
```

SQLite’s source documentation identifies `devtest` as the development-test target and `releasetest` as the broader release-testing target. ([SQLite][1])

Use `devtest`:

* before committing a substantial core change;
* after changing parser, pager, B-tree, VDBE, planner, or build logic;
* when a single test plus `test` does not provide enough configuration coverage.

For a small extension developed outside the core, `testfixture.exe test\extension.test` followed by `nmake ... test` is usually the more efficient iteration loop.

### Release test suite

Run:

```cmd
nmake /f Makefile.msc TCLDIR=C:\Tcl releasetest
```

This is substantially broader and slower than the ordinary suite. It runs multiple build configurations rather than merely repeating the same binary.

Use it for:

* release candidates;
* invasive SQLite-core modifications;
* changes to compile-time feature combinations;
* changes affecting multiple platforms or build modes.

SQLite officially lists `releasetest` as the full release-test target, though some configurations may have additional platform-specific requirements. ([SQLite][1])

### Debug and assertion-enabled testing

For development, build with SQLite debugging enabled:

```cmd
nmake /f Makefile.msc TCLDIR=C:\Tcl DEBUG=1 clean testfixture.exe
```

Then run the desired script:

```cmd
testfixture.exe test\your_test.test
```

For a more instrumentation-heavy debug build:

```cmd
nmake /f Makefile.msc TCLDIR=C:\Tcl DEBUG=3 clean testfixture.exe
```

SQLite’s Windows build instructions specifically use `DEBUG=3` for a debugging build that enables facilities such as `.treetrace` and `.wheretrace`. ([SQLite][1])

Do not reuse objects from a non-debug build. Put `clean` in the same invocation or run it beforehand:

```cmd
nmake /f Makefile.msc TCLDIR=C:\Tcl DEBUG=3 clean testfixture.exe
```

### Testing custom compile-time options

Pass SQLite preprocessor definitions through `OPTS` or `OPTIONS`, according to the variable used by the target and your checked-out `Makefile.msc`.

A typical test build is:

```cmd
nmake /f Makefile.msc TCLDIR=C:\Tcl clean
nmake /f Makefile.msc TCLDIR=C:\Tcl ^
  "OPTS=-DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_RTREE" ^
  testfixture.exe
```

Then:

```cmd
testfixture.exe test\your_test.test
```

SQLite documents command-line compile-time options using `OPTIONS=...`; its Windows DLL example uses `OPTS=...`. Check the local `Makefile.msc` definitions before standardizing your project wrapper. ([SQLite][1])

For your extra auto-extension build, for example:

```cmd
nmake /f Makefile.msc TCLDIR=C:\Tcl clean
nmake /f Makefile.msc TCLDIR=C:\Tcl ^
  "OPTS=-DSQLITE_EXTRA_AUTOEXT=sqlite3ExtraAutoExtInit" ^
  testfixture.exe
```

Any additional source integration must also be present in the test build’s source lists. Merely defining the entry-point macro is insufficient if `extra_autoext.c` and its extension sources are not compiled into `testfixture.exe`.

### Installing the SQLite Tcl extension

SQLite recommends, but does not require, installing its Tcl extension before running tests:

```cmd
nmake /f Makefile.msc TCLDIR=C:\Tcl tclextension-install
```

The test suite can run without this step, but SQLite notes that tests run more smoothly with the extension installed. The installed extension does not have to match the exact SQLite revision under test. ([SQLite][1])

This is normally a one-time environment setup step, not something to repeat for every build.

### Useful complete workflow

```cmd
@echo off
setlocal

set "SQLITE_SRC=B:\SQLite\Current\sqlite"
set "TCLDIR=C:\Tcl"
set "PATH=%TCLDIR%\bin;%PATH%"

cd /d "%SQLITE_SRC%" || exit /b 1

where cl      || exit /b 1
where nmake   || exit /b 1
where tclsh   || exit /b 1

nmake /nologo /f Makefile.msc TCLDIR="%TCLDIR%" clean || exit /b 1

nmake /nologo /f Makefile.msc ^
  TCLDIR="%TCLDIR%" ^
  DEBUG=1 ^
  testfixture.exe || exit /b 1

testfixture.exe test\main.test || exit /b 1

nmake /nologo /f Makefile.msc ^
  TCLDIR="%TCLDIR%" ^
  DEBUG=1 ^
  test || exit /b 1

endlocal
```

### Recommended testing levels

For extension implementation, use three levels:

#### Inner loop

```cmd
nmake /f Makefile.msc TCLDIR=C:\Tcl testfixture.exe
testfixture.exe test\pblob.test
```

#### Pre-commit

```cmd
nmake /f Makefile.msc TCLDIR=C:\Tcl clean
nmake /f Makefile.msc TCLDIR=C:\Tcl DEBUG=1 test
```

#### Milestone or release candidate

```cmd
nmake /f Makefile.msc TCLDIR=C:\Tcl clean
nmake /f Makefile.msc TCLDIR=C:\Tcl releasetest
```

The key point is that **the test build is not merely `sqlite3.exe`**. The primary harness is `testfixture.exe`, and the principal test inputs are the Tcl scripts under `test\`. SQLite’s canonical source tree and `Makefile.msc` manage the generated source files and test-only C modules required to construct that harness. ([SQLite][2])

[1]: https://sqlite.org/src/doc/trunk/doc/compile-for-windows.md "SQLite: Notes On Compiling SQLite On Windows 11"
[2]: https://sqlite.org/src/doc/trunk/README.md "SQLite: Documentation"

---
---

## 📗 SQLite Testing Makefile.msc Targets

Note: missing `sqlite3_checker.exe` target in `$(TESTPROGS)`

- smoketest (PREREQ: `$(TESTPROGS)`, should be `testfixture.exe`)

- coretestprogs
- testfixture.exe
- sqlite3_analyzer.exe
- sqldiff.exe
- dbhash.exe
- sqltclsh.exe
- testfixture.exe sqlite3_analyzer.exe sqldiff.exe dbhash.exe sqltclsh.exe

- devtest
- tcltest
- releasetest
- fuzztest
