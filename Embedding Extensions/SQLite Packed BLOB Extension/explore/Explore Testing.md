---
urls:
  - https://chatgpt.com/c/6a643d87-ce3c-83eb-891c-9e217ab8bd60
  - https://chatgpt.com/c/6a6618c4-48b0-83eb-851b-7a60f648fbae
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

---
---

## 📗 Alphabet Template Testing

You want two distinct test layers:

1. **C unit tests** for the private helper functions.
2. **SQL integration tests** for the complete extension contract through SQLite.

SQLite’s own primary development tests use Tcl, and an individual `.test` file can be run directly with `testfixture.exe`; you do not need to run SQLite’s entire test suite. ([SQLite][1])

### 1. Recommended project structure

```text
src/
    alphabet.c

test/
    unit/
        test_alphabet_helpers.c
    sql/
        alphabet.test
    run-tests.cmd
    README.md

build/
    sqlite/
    build/
        test/
            test_alphabet_helpers.exe
            alphabet.dll
```

For this project, a third-party C test framework is unnecessary. The helper surface is tiny, so a small assertion-based C test executable is sufficient.

### 2. Testing responsibilities

#### C unit tests

Test implementation-level contracts:

* `utf8_byte_count()`
* `utf8_length()`
* `utf8_byte_offset()`
* `alphabet_select()`

These tests may include `alphabet.c` directly so its `static` functions remain visible within the test translation unit.

#### SQL integration tests

Test everything observable by a user:

* registration
* accepted arities
* language selection
* case-insensitive selectors
* Unicode slicing
* positive and negative indexing
* length handling
* type validation
* range validation
* `NULL` behavior
* deterministic and innocuous registration behavior
* exact error messages

The SQL tests are the authoritative tests. A helper may work independently while the callback still applies the wrong indexing, type conversion, or error behavior.

---

### 3. C unit-test architecture

Create:

```text
test/unit/test_alphabet_helpers.c
```

Use:

```c
#define SQLITE_CORE
#include "../../src/alphabet.c"
```

Because the source is included directly, all `static` helpers are visible to the unit test.

Link this test executable with `sqlite3.c`. That is necessary because `alphabet.c` also contains references to public SQLite functions such as `sqlite3_stricmp()` and `sqlite3_create_function()`.

A minimal structure:

```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SQLITE_CORE
#include "../../src/alphabet.c"

static int nFailure = 0;

#define EXPECT_TRUE(expr)                                                \
  do{                                                                    \
    if( !(expr) ){                                                       \
      fprintf(stderr, "%s:%d: assertion failed: %s\n",                  \
              __FILE__, __LINE__, #expr);                               \
      ++nFailure;                                                        \
    }                                                                    \
  }while(0)

#define EXPECT_INT(expected, actual)                                     \
  do{                                                                    \
    sqlite3_int64 e_ = (expected);                                       \
    sqlite3_int64 a_ = (actual);                                         \
    if( e_!=a_ ){                                                        \
      fprintf(stderr,                                                    \
              "%s:%d: expected %lld, got %lld\n",                       \
              __FILE__, __LINE__,                                        \
              (long long)e_, (long long)a_);                            \
      ++nFailure;                                                        \
    }                                                                    \
  }while(0)

#define EXPECT_STRING(expected, actual)                                  \
  do{                                                                    \
    const char *e_ = (expected);                                         \
    const char *a_ = (actual);                                           \
    if( a_==0 || strcmp(e_, a_)!=0 ){                                    \
      fprintf(stderr,                                                    \
              "%s:%d: expected \"%s\", got \"%s\"\n",                   \
              __FILE__, __LINE__, e_, a_ ? a_ : "(null)");              \
      ++nFailure;                                                        \
    }                                                                    \
  }while(0)

static void test_utf8_byte_count(void){
  static const unsigned char ascii[] = "A";
  static const unsigned char twoByte[] = "А";
  static const unsigned char threeByte[] = "€";
  static const unsigned char fourByte[] = "😀";

  EXPECT_INT(1, utf8_byte_count(ascii));
  EXPECT_INT(2, utf8_byte_count(twoByte));
  EXPECT_INT(3, utf8_byte_count(threeByte));
  EXPECT_INT(4, utf8_byte_count(fourByte));
}

int main(void){
  test_utf8_byte_count();

  if( nFailure!=0 ){
    fprintf(stderr, "%d test(s) failed\n", nFailure);
    return EXIT_FAILURE;
  }

  puts("All helper tests passed.");
  return EXIT_SUCCESS;
}
```

Do not define `NDEBUG` for the unit-test build.

### 4. Helper test inventory

#### `utf8_byte_count()`

Test one valid representative of every UTF-8 width:

| Input | Code point | Expected |
| ----- | ---------: | -------: |
| `A`   |     U+0041 |        1 |
| `А`   |     U+0410 |        2 |
| `€`   |     U+20AC |        3 |
| `😀`  |    U+1F600 |        4 |

Do **not** test malformed leading bytes unless you decide malformed UTF-8 is part of this helper’s supported contract. The current implementation assumes a valid leading byte. Tests for unsupported inputs would merely freeze incidental behavior such as returning `4` for an invalid byte.

#### `utf8_length()`

Test:

```text
""       -> 0
"A"      -> 1
"ABC"    -> 3
"А"      -> 1
"АБВ"    -> 3
"AА€😀"  -> 4
LATIN_UTF8     -> 52
CYRILLIC_UTF8  -> 66
```

The mixed-width case is important. It demonstrates that the function advances separately over 1-, 2-, 3-, and 4-byte code points.

#### `utf8_byte_offset()`

For:

```text
"AА€😀"
```

test:

| Code-point index | Expected byte offset |
| ---------------: | -------------------: |
|                0 |                    0 |
|                1 |                    1 |
|                2 |                    3 |
|                3 |                    6 |
|                4 |                   10 |

Also test boundaries on both alphabet constants:

```c
EXPECT_INT(0, utf8_byte_offset(LATIN_UTF8, 0));
EXPECT_INT(52, utf8_byte_offset(LATIN_UTF8, 52));

EXPECT_INT(0, utf8_byte_offset(CYRILLIC_UTF8, 0));
EXPECT_INT(132, utf8_byte_offset(CYRILLIC_UTF8, 66));
```

Do not pass negative indices or indices beyond the code-point length. The helper’s documented precondition excludes them; range validation belongs to the SQL callback.

#### `alphabet_select()`

Test every accepted spelling:

```text
en
EN
eN
English
ENGLISH
eNgLiSh

ru
RU
rU
Russian
RUSSIAN
rUsSiAn
```

Verify exact pointer/string selection:

```c
EXPECT_TRUE(alphabet_select("en")==LATIN_UTF8);
EXPECT_TRUE(alphabet_select("Russian")==CYRILLIC_UTF8);
```

Test unsupported values:

```text
""
"eng"
"rus"
"English "
" English"
"de"
"русский"
```

Expected result:

```c
alphabet_select(...) == 0
```

The SQL callback, not this helper, converts that null pointer into an SQL error.

---

### 5. SQL testing with SQLite `testfixture`

SQLite’s canonical Tcl tests use `tester.tcl` and helpers such as:

* `do_execsql_test`
* `do_catchsql_test`
* `do_test`
* `finish_test`

The `testfixture` executable can run one test script directly, for example:

```cmd
testfixture.exe path\to\alphabet.test
```

That is the right mechanism for running only the alphabet tests. ([SQLite][2])

Build it on Windows with MSVC:

```cmd
set "TCLDIR=C:\Tcl"
nmake /f Makefile.msc testfixture.exe
```

SQLite documents `TCLDIR` for locating Tcl on Windows and `testfixture.exe` as the executable used for individual `.test` files. ([SQLite][2])

### 6. Loadable versus integrated test builds

Test both deployment forms, but not necessarily on every edit.

#### Primary development test

Build `alphabet.dll` and load it from the Tcl test.

This tests:

* `sqlite3_alphabet_init`
* `SQLITE_EXTENSION_INIT2`
* exported symbol naming
* loadable-extension registration
* actual extension binary boundaries

SQLite explicitly supports developing and testing extensions as separately loaded shared libraries. ([SQLite][3])

#### Integrated smoke test

Also build the extension into your customized SQLite/testfixture configuration periodically.

This tests:

* the `SQLITE_CORE` branch
* `sqlite3AlphabetInit`
* your static or auto-extension integration
* absence of symbol collisions

The same behavioral `.test` cases should run against both builds. Only the setup step should differ.

---

### 7. SQL test file skeleton

Conceptually:

```tcl
set sqlite_test_dir $::env(SQLITE_TEST_DIR)
source [file join $sqlite_test_dir tester.tcl]

set testprefix alphabet

set extension_path $::env(ALPHABET_EXTENSION)

db enable_load_extension 1
db eval {
  SELECT load_extension($extension_path, 'sqlite3_alphabet_init')
}

# Tests go here.

finish_test
```

The Tcl SQLite interface disables extension loading by default and provides `enable_load_extension` to enable it. ([SQLite][4])

Depending on the exact SQLite source checkpoint, `tester.tcl` may expect some conventional global variables. Keep the alphabet test outside the SQLite source tree, but provide the SQLite `test` directory through `SQLITE_TEST_DIR`.

---

### 8. SQL test modules

Organize test names by behavioral category:

```text
alphabet-1.*  registration and arity
alphabet-2.*  complete alphabet selection
alphabet-3.*  start indexing
alphabet-4.*  length handling
alphabet-5.*  combined start and length
alphabet-6.*  NULL handling
alphabet-7.*  invalid language inputs
alphabet-8.*  invalid start inputs
alphabet-9.*  invalid length inputs
alphabet-10.* UTF-8 correctness
alphabet-11.* SQL-context behavior
alphabet-12.* regression tests
```

### 9. Registration and arity

Test all registered arities:

```tcl
do_execsql_test alphabet-1.1 {
  SELECT alpha_string('en');
} {
  ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz
}

do_execsql_test alphabet-1.2 {
  SELECT alpha_string('en', 0);
} {
  ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz
}

do_execsql_test alphabet-1.3 {
  SELECT alpha_string('en', 0, 1);
} {
  A
}
```

Test rejected arities:

```tcl
do_catchsql_test alphabet-1.4 {
  SELECT alpha_string();
} {
  1 {wrong number of arguments to function alpha_string()}
}

do_catchsql_test alphabet-1.5 {
  SELECT alpha_string('en', 0, 1, 2);
} {
  1 {wrong number of arguments to function alpha_string()}
}
```

Exact SQLite wording may differ slightly by SQLite checkpoint. Confirm the message produced by your pinned checkpoint before freezing it into the expected result.

### 10. Language selectors

Test every documented selector:

```sql
alpha_string('en')
alpha_string('English')
alpha_string('ru')
alpha_string('Russian')
```

Test representative case variants:

```sql
alpha_string('EN')
alpha_string('english')
alpha_string('eNgLiSh')
alpha_string('RU')
alpha_string('russian')
alpha_string('rUsSiAn')
```

Do not test every possible casing. Use equivalence classes:

* all lowercase
* all uppercase
* mixed case

Verify exact complete strings and exact lengths:

```tcl
do_execsql_test alphabet-2.10 {
  SELECT
    length(alpha_string('en')),
    length(alpha_string('ru'));
} {
  52 66
}
```

This catches accidental missing, duplicated, or reordered letters.

### 11. Start-index tests

For each alphabet, test:

|    Start | Expected behavior     |
| -------: | --------------------- |
|  omitted | entire alphabet       |
|      `0` | entire alphabet       |
|      `1` | omit first code point |
|   middle | expected tail         |
|    `n-1` | final code point      |
|      `n` | empty string          |
|     `-1` | final code point      |
|     `-2` | final two code points |
|     `-n` | entire alphabet       |
|    `n+1` | error                 |
| `-(n+1)` | error                 |

For Latin, `n == 52`; for Cyrillic, `n == 66`.

Examples:

```tcl
do_execsql_test alphabet-3.1 {
  SELECT alpha_string('en', 51);
} {
  z
}

do_execsql_test alphabet-3.2 {
  SELECT alpha_string('en', -1);
} {
  z
}

do_execsql_test alphabet-3.3 {
  SELECT alpha_string('ru', -1);
} {
  я
}

do_execsql_test alphabet-3.4 {
  SELECT quote(alpha_string('en', 52));
} {
  {''}
}

do_catchsql_test alphabet-3.5 {
  SELECT alpha_string('en', 53);
} {
  1 {alpha_string() start index is out of range}
}

do_catchsql_test alphabet-3.6 {
  SELECT alpha_string('en', -53);
} {
  1 {alpha_string() start index is out of range}
}
```

Use `quote()` when testing empty strings so they cannot be confused with an empty result list.

### 12. Length tests

Test:

|                 Length | Expected        |
| ---------------------: | --------------- |
|                    `0` | empty string    |
|                    `1` | one code point  |
|    less than remaining | exact substring |
|     equal to remaining | entire tail     |
| greater than remaining | entire tail     |
|               negative | error           |

Examples:

```tcl
do_execsql_test alphabet-4.1 {
  SELECT quote(alpha_string('en', 0, 0));
} {
  {''}
}

do_execsql_test alphabet-4.2 {
  SELECT alpha_string('en', 0, 1);
} {
  A
}

do_execsql_test alphabet-4.3 {
  SELECT alpha_string('en', 25, 3);
} {
  Zab
}

do_execsql_test alphabet-4.4 {
  SELECT alpha_string('ru', 0, 3);
} {
  АБВ
}

do_execsql_test alphabet-4.5 {
  SELECT alpha_string('en', 50, 1000);
} {
  yz
}

do_catchsql_test alphabet-4.6 {
  SELECT alpha_string('en', 0, -1);
} {
  1 {alpha_string() length must not be negative}
}
```

The `25, 3` case crosses from uppercase to lowercase and is a useful boundary regression.

### 13. Combined negative-start and length tests

These are important because they combine normalization and truncation:

```sql
alpha_string('en', -5, 2)  -> "vw"
alpha_string('en', -5, 5)  -> "vwxyz"
alpha_string('en', -5, 20) -> "vwxyz"

alpha_string('ru', -5, 2)
alpha_string('ru', -5, 5)
alpha_string('ru', -5, 20)
```

Also test:

```sql
alpha_string('en', 52, 0)   -> ''
alpha_string('en', 52, 10)  -> ''
alpha_string('en', -52, 52) -> complete alphabet
```

### 14. `NULL` tests

Your current documented implementation propagates `NULL` from any supplied argument.

Test:

```sql
alpha_string(NULL)
alpha_string(NULL, 0)
alpha_string(NULL, 0, 1)
alpha_string('en', NULL)
alpha_string('en', NULL, 1)
alpha_string('en', 0, NULL)
```

Use:

```tcl
do_execsql_test alphabet-6.1 {
  SELECT alpha_string(NULL) IS NULL;
} {
  1
}
```

Repeat for each position.

This is preferable to expecting a blank Tcl value because SQL `NULL` and an empty string are different.

### 15. Invalid language tests

#### Wrong SQL storage classes

Test:

```sql
alpha_string(1)
alpha_string(1.5)
alpha_string(x'656e')
```

Expected:

```text
alpha_string() language must be text
```

#### Unsupported text

Test:

```sql
alpha_string('')
alpha_string('de')
alpha_string('eng')
alpha_string('rus')
alpha_string(' English')
alpha_string('English ')
alpha_string('русский')
```

Expected:

```text
alpha_string() language must be en, English, ru, or Russian
```

The whitespace cases establish that selectors are exact and are not silently trimmed.

### 16. Invalid `start` tests

Test wrong storage classes:

```sql
alpha_string('en', 1.0)
alpha_string('en', '1')
alpha_string('en', x'31')
```

Expected:

```text
alpha_string() start must be an integer
```

Also test both range directions:

```sql
alpha_string('en', 53)
alpha_string('en', -53)
alpha_string('ru', 67)
alpha_string('ru', -67)
```

Expected:

```text
alpha_string() start index is out of range
```

Test extreme integers:

```sql
alpha_string('en', 9223372036854775807)
alpha_string('en', -9223372036854775808)
```

These verify that the range expression does not overflow.

### 17. Invalid `length` tests

Wrong storage classes:

```sql
alpha_string('en', 0, 1.0)
alpha_string('en', 0, '1')
alpha_string('en', 0, x'31')
```

Expected:

```text
alpha_string() length must be an integer
```

Negative values:

```sql
alpha_string('en', 0, -1)
alpha_string('en', 0, -9223372036854775808)
```

Expected:

```text
alpha_string() length must not be negative
```

Large positive value:

```sql
alpha_string('en', 0, 9223372036854775807)
```

Expected: entire alphabet, without overflow.

### 18. UTF-8-specific SQL tests

Cyrillic tests must prove that slicing counts code points rather than bytes:

```tcl
do_execsql_test alphabet-10.1 {
  SELECT alpha_string('ru', 0, 1);
} {
  А
}

do_execsql_test alphabet-10.2 {
  SELECT alpha_string('ru', 1, 1);
} {
  Б
}

do_execsql_test alphabet-10.3 {
  SELECT alpha_string('ru', -1, 1);
} {
  я
}

do_execsql_test alphabet-10.4 {
  SELECT
    length(alpha_string('ru', 0, 10)),
    length(CAST(alpha_string('ru', 0, 10) AS BLOB));
} {
  10 20
}
```

The final test confirms that ten Cyrillic code points occupy twenty UTF-8 bytes.

### 19. SQL-context tests

Test that the function works in normal SQLite expressions:

```sql
SELECT upper(alpha_string('en', 26, 3));
SELECT alpha_string('en', 0, 3) || '-';
SELECT length(alpha_string('ru', 5, 10));
```

Test over table rows:

```sql
WITH languages(language) AS (
  VALUES ('en'), ('ru')
)
SELECT language, length(alpha_string(language))
FROM languages
ORDER BY language;
```

Test that an invalid row aborts execution:

```sql
WITH languages(language) AS (
  VALUES ('en'), ('invalid'), ('ru')
)
SELECT alpha_string(language)
FROM languages;
```

Expected: SQL error, not a `NULL` result for the invalid row.

### 20. Registration-property tests

Since the function is registered as deterministic, SQLite should allow it in contexts requiring deterministic functions, such as an expression index:

```tcl
do_execsql_test alphabet-11.1 {
  CREATE TABLE t1(language TEXT);
  CREATE INDEX t1_alpha
    ON t1(alpha_string(language, 0, 1));
} {}
```

Application-defined functions are registered through `sqlite3_create_function()` with function-property flags such as determinism and innocuousness. ([SQLite][5])

For innocuous behavior, test schema use with trusted schema disabled:

```sql
PRAGMA trusted_schema = OFF;

CREATE TABLE t2(
  language TEXT,
  initial TEXT GENERATED ALWAYS AS (
    alpha_string(language, 0, 1)
  ) STORED
);
```

Whether this exact schema form is accepted can also depend on the SQLite checkpoint and other flags, so treat it as a deployment-policy test rather than a core functional test.

---

### 21. Do not test every integer

“All valid combinations” cannot literally mean every value because `start` and `length` are 64-bit integers.

Use equivalence classes and boundaries:

* below valid range
* first valid value
* ordinary interior value
* last valid value
* immediately above valid range
* minimum 64-bit integer
* maximum 64-bit integer

This provides stronger coverage than many arbitrary values.

### 22. Suggested development cadence

Run on every source change:

```text
1. Compile with warnings as errors.
2. Run helper unit tests.
3. Run alphabet.test against the loadable DLL.
```

Run before a release:

```text
1. Debug build.
2. Release build.
3. Loadable-extension test.
4. Integrated SQLITE_CORE test.
5. 32-bit MSVC build, if supported.
6. 64-bit MSVC build.
7. Fresh SQLite checkpoint compatibility build.
```

SQLite itself uses multiple platforms and configurations before release, but you only need a focused subset appropriate to this extension. ([SQLite][1])

### 23. MSVC compilation outline

Helper test:

```cmd
cl.exe /nologo /W4 /WX /Od /Zi ^
  /I build\sqlite ^
  test\unit\test_alphabet_helpers.c ^
  build\sqlite\sqlite3.c ^
  /Fe:build\build\test\test_alphabet_helpers.exe
```

Loadable extension:

```cmd
cl.exe /nologo /W4 /WX /LD ^
  /I build\sqlite ^
  src\alphabet.c ^
  /link /OUT:build\build\test\alphabet.dll
```

Run:

```cmd
build\build\test\test_alphabet_helpers.exe

set "SQLITE_TEST_DIR=%CD%\build\sqlite\test"
set "ALPHABET_EXTENSION=%CD%\build\build\test\alphabet.dll"

build\build\testfixture.exe test\sql\alphabet.test
```

The final goal should be one command:

```cmd
test\run-tests.cmd
```

That script should build the two artifacts, execute both test layers, propagate the first nonzero exit status, and leave all generated files under ignored `build\build\test`.

[1]: https://www.sqlite.org/testing.html "How SQLite Is Tested"
[2]: https://www3.sqlite.org/src "SQLite: Documentation"
[3]: https://www.sqlite.org/loadext.html "Run-Time Loadable Extensions"
[4]: https://www.sqlite.org/tclsqlite.html "The Tcl interface to the SQLite library"
[5]: https://www.sqlite.org/appfunc.html "Application-Defined SQL Functions"

