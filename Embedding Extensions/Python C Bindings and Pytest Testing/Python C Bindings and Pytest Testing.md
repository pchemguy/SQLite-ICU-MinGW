---
url: https://chatgpt.com/c/6a67af23-5958-83eb-8a16-8b6ab3f76199
---

## 📗 Calling C DLL

Yes. The correct mechanism is a **generated test translation unit** that includes the production `.c` file and defines externally visible wrappers around selected `static` routines.

A separately compiled C module cannot portably access `static` functions from `alphabet.c`. The generated module must therefore compile the contents of `alphabet.c` into its own translation unit:

```text
alphabet_test_api.c
    ├── includes alphabet.c
    └── defines exported wrapper functions
```

For the test build, compile `alphabet_test_api.c` **instead of compiling `alphabet.c` separately**. Otherwise, the non-static production symbols such as `sqlite3AlphabetInit()` would be defined twice.

### Generated wrapper module

For this source, an automatically generated wrapper could look like this:

```c
/*
** Generated test interface for src/alphabet.c.
**
** Do not edit manually.
*/

#include <stddef.h>
#include <stdint.h>

/*
** Compile the production implementation into this translation unit.
** This makes its file-local static functions callable by wrappers below.
*/
#include "../../src/alphabet.c"

#if defined(_WIN32)
## define TEST_API __declspec(dllexport)
#else
## define TEST_API __attribute__((visibility("default")))
#endif

/*
** Wrapper for:
**
**   static int utf8_byte_count(const unsigned char *z);
*/
TEST_API int test_alphabet_utf8_byte_count(
  const unsigned char *z
){
  if( z==0 ){
    return -1;
  }

  return utf8_byte_count(z);
}

/*
** Wrapper for:
**
**   static sqlite3_int64 utf8_length(const char *z);
*/
TEST_API int64_t test_alphabet_utf8_length(
  const char *z
){
  if( z==0 ){
    return -1;
  }

  return (int64_t)utf8_length(z);
}

/*
** Wrapper for:
**
**   static int utf8_byte_offset(
**     const char *z,
**     sqlite3_int64 i
**   );
*/
TEST_API int test_alphabet_utf8_byte_offset(
  const char *z,
  int64_t i
){
  if( z==0 || i<0 ){
    return -1;
  }

  return utf8_byte_offset(z, (sqlite3_int64)i);
}

/*
** Wrapper for:
**
**   static const char *alphabet_select(
**     const char *zLanguage
**   );
**
** The returned pointer refers to static storage owned by alphabet.c.
*/
TEST_API const char *test_alphabet_select(
  const char *zLanguage
){
  if( zLanguage==0 ){
    return 0;
  }

  return alphabet_select(zLanguage);
}
```

This does not modify `alphabet.c`, remove `static`, or introduce a production header.

### Why inclusion works

In C, `static` at file scope gives a function internal linkage, but the function remains callable anywhere within the same translation unit.

After preprocessing, the generated file effectively becomes:

```c
static int utf8_byte_count(...){
  ...
}

static sqlite3_int64 utf8_length(...){
  ...
}

TEST_API int64_t test_alphabet_utf8_length(const char *z){
  return utf8_length(z);
}
```

The wrapper can therefore call the private function directly.

A conventional separate source file containing only:

```c
extern sqlite3_int64 utf8_length(const char *);
```

would not work. `utf8_length()` has internal linkage and is not exported by the object file.

### Python interface through `ctypes`

The generated module can be compiled as a plain DLL and loaded directly:

```python
from __future__ import annotations

import ctypes
from pathlib import Path

import pytest


@pytest.fixture(scope="session")
def alphabet_api() -> ctypes.CDLL:
    dll_path = Path(__file__).parents[1] / "build" / "alphabet_test_api.dll"
    library = ctypes.CDLL(str(dll_path))

    library.test_alphabet_utf8_byte_count.argtypes = [
        ctypes.POINTER(ctypes.c_ubyte),
    ]
    library.test_alphabet_utf8_byte_count.restype = ctypes.c_int

    library.test_alphabet_utf8_length.argtypes = [
        ctypes.c_char_p,
    ]
    library.test_alphabet_utf8_length.restype = ctypes.c_int64

    library.test_alphabet_utf8_byte_offset.argtypes = [
        ctypes.c_char_p,
        ctypes.c_int64,
    ]
    library.test_alphabet_utf8_byte_offset.restype = ctypes.c_int

    library.test_alphabet_select.argtypes = [
        ctypes.c_char_p,
    ]
    library.test_alphabet_select.restype = ctypes.c_char_p

    return library
```

Tests then directly exercise the private routines:

```python
def test_utf8_length_ascii(alphabet_api):
    assert alphabet_api.test_alphabet_utf8_length(b"ABC") == 3


def test_utf8_length_cyrillic(alphabet_api):
    text = "АБВГД".encode("utf-8")
    assert alphabet_api.test_alphabet_utf8_length(text) == 5


@pytest.mark.parametrize(
    ("index", "expected"),
    [
        (0, 0),
        (1, 2),
        (2, 4),
        (5, 10),
    ],
)
def test_utf8_byte_offset_cyrillic(
    alphabet_api,
    index: int,
    expected: int,
):
    text = "АБВГД".encode("utf-8")

    assert (
        alphabet_api.test_alphabet_utf8_byte_offset(text, index)
        == expected
    )


@pytest.mark.parametrize(
    ("language", "expected"),
    [
        (b"en", b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"),
        (b"EN", b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"),
        (b"English", b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"),
        (
            "ru".encode(),
            (
                "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ"
                "абвгдеёжзийклмнопрстуфхцчшщъыьэюя"
            ).encode("utf-8"),
        ),
    ],
)
def test_alphabet_select(
    alphabet_api,
    language: bytes,
    expected: bytes,
):
    assert alphabet_api.test_alphabet_select(language) == expected


def test_alphabet_select_rejects_unknown_language(alphabet_api):
    assert alphabet_api.test_alphabet_select(b"de") is None
```

### Build implications

Because `alphabet.c` includes SQLite declarations and calls `sqlite3_stricmp()`, the wrapper DLL still needs SQLite integration.

There are two possible test artifacts.

#### Wrapper included in the complete SQLite test build

Add the generated wrapper source to the same SQLite build that integrates `alphabet.c`.

In that case, the build arrangement must ensure that `alphabet.c` is included only once:

```text
SQLite test build sources:
    sqlite3.c
    alphabet_test_api.c   ← internally includes alphabet.c
```

Do not also add:

```text
alphabet.c
```

as a separate compilation unit.

The resulting `sqlite3.dll` can export both normal SQLite symbols and test wrapper symbols:

```text
sqlite3_open
sqlite3_prepare_v2
...
test_alphabet_utf8_length
test_alphabet_utf8_byte_offset
test_alphabet_select
```

Python can then load the same DLL through `ctypes.WinDLL()` or `ctypes.CDLL()` while `_sqlite3.pyd` uses it as SQLite.

#### Separate test wrapper DLL

Alternatively:

```text
alphabet_test_api.dll
    ├── alphabet_test_api.c
    │     └── includes alphabet.c
    └── links to sqlite3.lib
```

This is structurally cleaner because test-only exports do not pollute `sqlite3.dll`.

However, it compiles another copy of the production implementation into the wrapper DLL. That is normally acceptable for unit testing private routines, but it is not the exact copy embedded in the target SQLite DLL.

Given your stated approach, adding the wrapper source to the test SQLite build is the closer match.

### Automatic generation

This can be automated, but “automatic” needs a source of truth identifying the target routines and their Python-facing signatures.

For example, a manifest:

```toml
[source]
path = "src/alphabet.c"
prefix = "test_alphabet"

[[function]]
target = "utf8_byte_count"
wrapper = "utf8_byte_count"
return = "int"
parameters = [
    "const unsigned char *z",
]

[[function]]
target = "utf8_length"
wrapper = "utf8_length"
return = "int64_t"
parameters = [
    "const char *z",
]

[[function]]
target = "utf8_byte_offset"
wrapper = "utf8_byte_offset"
return = "int"
parameters = [
    "const char *z",
    "int64_t i",
]

[[function]]
target = "alphabet_select"
wrapper = "alphabet_select"
return = "const char *"
parameters = [
    "const char *zLanguage",
]
```

The generator can produce:

1. `alphabet_test_api.c`;
2. `alphabet_test_api.py` containing `ctypes` declarations;
3. optionally, pytest fixtures;
4. optionally, an export definition file for MSVC.

Purely parsing arbitrary C and creating safe Python bindings without metadata is not generally reliable because the generator cannot infer:

* pointer ownership;
* buffer lengths;
* nullability;
* whether an output pointer is input, output, or both;
* valid index ranges;
* string encoding;
* whether returned storage must be freed;
* whether callbacks or opaque structures need special handling.

But for scalar routines using integers and NUL-terminated strings, generation from a concise manifest is straightforward.

### MSVC exports

For a dedicated wrapper DLL, `__declspec(dllexport)` is sufficient.

When including wrappers in the SQLite DLL, it may be preferable to generate a module-definition fragment:

```def
EXPORTS
    test_alphabet_utf8_byte_count
    test_alphabet_utf8_length
    test_alphabet_utf8_byte_offset
    test_alphabet_select
```

or retain `__declspec(dllexport)` on every generated wrapper.

Use `cdecl`, which is the default for ordinary C functions. Python should load it with:

```python
ctypes.CDLL(...)
```

rather than `ctypes.WinDLL(...)`, which assumes `stdcall`.

### Important limitations

The generator should not manufacture defensive behavior unless the test API contract defines it. For example:

```c
if( z==0 ){
  return -1;
}
```

changes the observable interface compared with the private function, which assumes valid input. There are two valid wrapper policies:

**Transparent wrappers**

```c
TEST_API int64_t test_alphabet_utf8_length(const char *z){
  return (int64_t)utf8_length(z);
}
```

These preserve the private function contract exactly.

**Protected wrappers**

```c
TEST_API int64_t test_alphabet_utf8_length(const char *z){
  if( z==0 ) return -1;
  return (int64_t)utf8_length(z);
}
```

These are safer across the Python boundary but introduce wrapper semantics.

For rigorous unit testing, I would generate transparent wrappers by default and permit optional validation in the manifest.

### Recommended test-build structure

```text
TOP/
├── src/
│   └── alphabet.c
├── pytestenv/
│   ├── src/
│   │   └── pytestenv/
│   │       └── __init__.py
│   └── tests/
│       ├── conftest.py
│       ├── test_alphabet_select.py
│       ├── test_utf8_byte_count.py
│       ├── test_utf8_byte_offset.py
│       └── test_utf8_length.py
├── test_support/
│   ├── alphabet_test_api.toml
│   ├── generate_test_api.py
│   └── generated/
│       └── alphabet_test_api.c
└── build/
    └── ...
```

The essential technique is therefore:

```c
#include "../../src/alphabet.c"

/* Generated external aliases follow. */
TEST_API int64_t test_alphabet_utf8_length(const char *z){
  return utf8_length(z);
}
```

That is the portable way to expose selected private C routines without modifying the production module.

---
---

## 📗 C Wrapper

Correct. I misunderstood the build topology.

The generated wrapper source is **not compiled separately** and does **not include `alphabet.c`**. Instead, both files are incorporated into the generated SQLite amalgamation, in this order:

```text
sqlite3.c generated from:

    SQLite core sources
    alphabet.c
    alphabet_test_wrappers.c
```

Because the amalgamation is one translation unit, the wrappers placed after `alphabet.c` can call its `static` functions directly.

Conceptually, the resulting amalgamation contains:

```c
static int utf8_byte_count(const unsigned char *z){
  ...
}

static sqlite3_int64 utf8_length(const char *z){
  ...
}

static int utf8_byte_offset(const char *z, sqlite3_int64 i){
  ...
}

static const char *alphabet_select(const char *zLanguage){
  ...
}

/* Generated test wrappers follow later in the same sqlite3.c. */

__declspec(dllexport)
sqlite3_int64 alphabet_test_utf8_length(const char *z){
  return utf8_length(z);
}
```

### Generated wrapper source

The generated file can contain only wrappers:

```c
/*
** Generated test wrappers for alphabet.c.
**
** This file is incorporated into the SQLite amalgamation after alphabet.c.
** It is not a standalone translation unit.
*/

#ifdef _WIN32
# define PYTEST_EXPORT __declspec(dllexport)
#else
# define PYTEST_EXPORT __attribute__((visibility("default")))
#endif

PYTEST_EXPORT int alphabet_test_utf8_byte_count(
  const unsigned char *z
){
  return utf8_byte_count(z);
}

PYTEST_EXPORT sqlite3_int64 alphabet_test_utf8_length(
  const char *z
){
  return utf8_length(z);
}

PYTEST_EXPORT int alphabet_test_utf8_byte_offset(
  const char *z,
  sqlite3_int64 i
){
  return utf8_byte_offset(z, i);
}

PYTEST_EXPORT const char *alphabet_test_alphabet_select(
  const char *zLanguage
){
  return alphabet_select(zLanguage);
}
```

It needs no includes because, at its insertion point in the amalgamation:

* SQLite types are already declared;
* `alphabet.c` has already been incorporated;
* its `static` routines are already defined;
* everything belongs to the same translation unit.

### Essential ordering constraint

This works only when the generated wrapper file appears **after** the target source:

```text
alphabet.c
alphabet_test_wrappers.c
```

This ordering would fail:

```text
alphabet_test_wrappers.c
alphabet.c
```

unless the wrapper generator also emitted compatible forward declarations. Even then, preserving target-before-wrapper ordering is simpler and avoids having to reproduce private declarations.

### Python access

Python can load the resulting `sqlite3.dll` directly with `ctypes`:

```python
import ctypes
from pathlib import Path

sqlite_dll = ctypes.CDLL(
    str(Path(__file__).parent / "sqlite3.dll")
)

sqlite_dll.alphabet_test_utf8_length.argtypes = [
    ctypes.c_char_p,
]
sqlite_dll.alphabet_test_utf8_length.restype = ctypes.c_int64

assert sqlite_dll.alphabet_test_utf8_length(b"ABC") == 3
```

For `alphabet_select()`:

```python
sqlite_dll.alphabet_test_alphabet_select.argtypes = [
    ctypes.c_char_p,
]
sqlite_dll.alphabet_test_alphabet_select.restype = ctypes.c_char_p

assert (
    sqlite_dll.alphabet_test_alphabet_select(b"en")
    == b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
)
```

### Automatic generation model

The generator needs to know which private functions to expose. A compact manifest is sufficient:

```toml
source = "alphabet.c"
prefix = "alphabet_test"

[[wrapper]]
target = "utf8_byte_count"
return_type = "int"
parameters = ["const unsigned char *z"]

[[wrapper]]
target = "utf8_length"
return_type = "sqlite3_int64"
parameters = ["const char *z"]

[[wrapper]]
target = "utf8_byte_offset"
return_type = "int"
parameters = [
  "const char *z",
  "sqlite3_int64 i",
]

[[wrapper]]
target = "alphabet_select"
return_type = "const char *"
parameters = ["const char *zLanguage"]
```

The generator then emits direct forwarding functions:

```c
PYTEST_EXPORT sqlite3_int64 alphabet_test_utf8_length(
  const char *z
){
  return utf8_length(z);
}
```

It can also generate the corresponding Python `ctypes` declarations.

### Build integration

The source list supplied to the amalgamation generator should effectively contain:

```text
alphabet.c
alphabet_test_wrappers.c
```

The wrapper file should be present only in test builds. A production build would incorporate:

```text
alphabet.c
```

while a pytest build would incorporate:

```text
alphabet.c
alphabet_test_wrappers.c
```

The final test artifact remains a normal `sqlite3.dll`, but it additionally exports test aliases for selected private routines.

That is the correct architecture: **generated wrapper fragments incorporated after their target modules into the same SQLite amalgamation translation unit**.


---
---

## 📗 Conditional Declaration

Yes. That is simpler and probably preferable here.

Keep the original private definitions and add test-only exported forwarding functions in the same module:

```c
static sqlite3_int64 utf8_length(const char *z){
  ...
}

#ifdef SQLITE_TEST

# if defined(_WIN32)
#  define ALPHABET_TEST_API __declspec(dllexport)
# else
#  define ALPHABET_TEST_API
# endif

ALPHABET_TEST_API sqlite3_int64
sqlite3AlphabetTestUtf8Length(const char *z){
  return utf8_length(z);
}

#endif
```

Likewise:

```c
#ifdef SQLITE_TEST

ALPHABET_TEST_API int
sqlite3AlphabetTestUtf8ByteCount(const unsigned char *z){
  return utf8_byte_count(z);
}

ALPHABET_TEST_API int
sqlite3AlphabetTestUtf8ByteOffset(
  const char *z,
  sqlite3_int64 i
){
  return utf8_byte_offset(z, i);
}

ALPHABET_TEST_API const char *
sqlite3AlphabetTestSelect(const char *zLanguage){
  return alphabet_select(zLanguage);
}

#endif
```

The production functions remain:

```c
static int utf8_byte_count(...);
static sqlite3_int64 utf8_length(...);
static int utf8_byte_offset(...);
static const char *alphabet_select(...);
```

The test build adds exported aliases only when built with:

```cmd
-DSQLITE_TEST
```

Python then calls the aliases through `ctypes`:

```python
import ctypes

sqlite = ctypes.CDLL("sqlite3.dll")

sqlite.sqlite3AlphabetTestUtf8Length.argtypes = [ctypes.c_char_p]
sqlite.sqlite3AlphabetTestUtf8Length.restype = ctypes.c_int64
```

### “Dual declarations” alternative

You can also change linkage conditionally:

```c
#ifdef SQLITE_TEST
# define ALPHABET_PRIVATE
#else
# define ALPHABET_PRIVATE static
#endif

ALPHABET_PRIVATE sqlite3_int64 utf8_length(const char *z){
  ...
}
```

This exposes the **original symbol** in test builds:

```c
#ifdef SQLITE_TEST
sqlite3_int64 utf8_length(const char *z);
#else
static sqlite3_int64 utf8_length(const char *z);
#endif
```

However, on Windows, removing `static` alone does not necessarily export the symbol from `sqlite3.dll`. You would still need `__declspec(dllexport)` or an entry in a `.def` file:

```c
#ifdef SQLITE_TEST
# define ALPHABET_PRIVATE __declspec(dllexport)
#else
# define ALPHABET_PRIVATE static
#endif
```

That produces:

```c
ALPHABET_PRIVATE sqlite3_int64 utf8_length(const char *z){
  ...
}
```

### Better choice: aliases rather than changing linkage

Exported test aliases are generally cleaner:

```c
static sqlite3_int64 utf8_length(const char *z){
  ...
}

#ifdef SQLITE_TEST
__declspec(dllexport)
sqlite3_int64 sqlite3AlphabetTestUtf8Length(const char *z){
  return utf8_length(z);
}
#endif
```

Advantages:

* production routines remain genuinely private in every build;
* test symbol names are clearly namespaced;
* generic names such as `utf8_length` cannot collide in the amalgamation;
* the original implementation declarations remain unchanged;
* the test ABI can use Python-friendly types independently of internal types;
* test-only exports are obvious when inspecting the DLL.

So, yes: no generated secondary module is required. A test-only wrapper section guarded by `SQLITE_TEST` directly in `alphabet.c` is the most straightforward design.

---

Correct. No wrapper is needed.

Use a conditional **forward declaration** to select linkage/export status, followed by the single unchanged definition:

```c
#ifdef SQLITE_TEST
__declspec(dllexport)
sqlite3_int64 utf8_length(const char *z);
#else
static sqlite3_int64 utf8_length(const char *z);
#endif

sqlite3_int64 utf8_length(const char *z){
  const unsigned char *p = (const unsigned char *)z;
  sqlite3_int64 n = 0;

  while( *p!=0 ){
    p += utf8_byte_count(p);
    ++n;
  }
  return n;
}
```

The first declaration determines the linkage:

* normal build: `utf8_length` has internal linkage;
* `SQLITE_TEST` build: the exact original function has external linkage and is exported;
* there is one implementation;
* there is no alias or forwarding wrapper.

For all target routines:

```c
#ifdef SQLITE_TEST
# if defined(_WIN32)
#  define ALPHABET_PRIVATE_DECL(type, name, args) \
     __declspec(dllexport) type name args
# else
#  define ALPHABET_PRIVATE_DECL(type, name, args) \
     __attribute__((visibility("default"))) type name args
# endif
#else
# define ALPHABET_PRIVATE_DECL(type, name, args) \
    static type name args
#endif
```

Then:

```c
ALPHABET_PRIVATE_DECL(
  int,
  utf8_byte_count,
  (const unsigned char *z)
);

ALPHABET_PRIVATE_DECL(
  sqlite3_int64,
  utf8_length,
  (const char *z)
);

ALPHABET_PRIVATE_DECL(
  int,
  utf8_byte_offset,
  (const char *z, sqlite3_int64 i)
);

ALPHABET_PRIVATE_DECL(
  const char *,
  alphabet_select,
  (const char *zLanguage)
);
```

Definitions remain ordinary and singular:

```c
int utf8_byte_count(const unsigned char *z){
  ...
}

sqlite3_int64 utf8_length(const char *z){
  ...
}

int utf8_byte_offset(const char *z, sqlite3_int64 i){
  ...
}

const char *alphabet_select(const char *zLanguage){
  ...
}
```

In the normal build, each definition inherits internal linkage from its prior `static` declaration. In the test build, it inherits external linkage from the exported declaration. Python can call the original functions directly through `ctypes`.

---

Yes. Use it directly on the declaration/definition:

```c
#ifdef SQLITE_TEST
# if defined(_WIN32)
#  define STAT_TEST_EXP __declspec(dllexport)
# else
#  define STAT_TEST_EXP __attribute__((visibility("default")))
# endif
#else
# define STAT_TEST_EXP static
#endif
```

Then:

```c
STAT_TEST_EXP sqlite3_int64 utf8_length(const char *z){
  const unsigned char *p = (const unsigned char *)z;
  sqlite3_int64 n = 0;

  while( *p!=0 ){
    p += utf8_byte_count(p);
    ++n;
  }
  return n;
}
```

Behavior:

* normal build: expands to `static`;
* Windows test build: expands to `__declspec(dllexport)`;
* non-Windows test build: external linkage with default visibility.

No separate declaration is required.

One caveat: on non-Windows platforms, `visibility("default")` affects symbol visibility, not linkage. Since there is no `static` in that expansion, the function has external linkage, which is exactly what you need.

A slightly clearer name would be:

```c
SQLITE_TEST_EXPORT
```

or, since it alternates between private and exported linkage:

```c
SQLITE_PRIVATE_OR_TEST_EXPORT
```

But mechanically, your macro is correct.

---

```c_
#ifdef SQLITE_TEST
# if defined(_WIN32)
#  define PYTEST_EXPORT __declspec(dllexport)
# else
#  define PYTEST_EXPORT __attribute__((visibility("default")))
# endif
#else
# define PYTEST_EXPORT static
#endif
```
