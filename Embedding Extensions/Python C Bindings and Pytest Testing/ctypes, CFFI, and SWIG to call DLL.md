---
url: https://chatgpt.com/c/6a683465-21cc-83eb-942f-54fe28dfe936
---

## 📗 ctypes, CFFI, and SWIG to call DLL

> [!NOTE] Prompt
> 
> Give me comprehensive overview of how I can use CFFI, SWIG, and ctypes to call DLL methods and access variables. Also include details how C methods and variables needs to be exported for such access. The primary focus is robust testing of C code in DLL via pytest. I need a simple flexible route to systematic testing of C code with minimal overhead via pytest. The nicety of DLL access is secondary. 

### Recommended approach

For **systematic pytest testing of C routines compiled into a DLL**, begin with **`ctypes`**.

It provides the lowest-overhead path:

1. Export selected internal routines only in test builds.
2. Build the normal DLL with a test-specific macro such as `SQLITE_TEST`.
3. Load the DLL in a session-scoped pytest fixture.
4. Declare each function’s `argtypes` and `restype`.
5. Use ordinary pytest parametrization for test cases.

Use **CFFI ABI mode** instead when your interface contains many structures, pointers, callbacks, or declarations that are easier to express as C syntax. CFFI supports direct access to declared functions and global variables through a loaded library object. Its ABI mode resembles `ctypes`; its API mode adds a compilation step and performs stronger compile-time checking. ([CFFI][1])

Use **SWIG** when you are creating a substantial, durable Python binding—particularly for a large C++ API—not merely a test harness. It generates a Python extension and a Python-facing wrapper layer, but introduces substantially more machinery than is normally justified for testing a small C module. SWIG can also expose global variables, ordinarily through its Python `cvar` object. ([Swig][2])

#### Practical ranking for your use case

| Criterion                             |             `ctypes` |             CFFI ABI |                   CFFI API |                    SWIG |
| ------------------------------------- | -------------------: | -------------------: | -------------------------: | ----------------------: |
| Initial setup                         |          **Minimal** |                  Low |                   Moderate |                    High |
| Additional generated C code           |                 None |                 None |                        Yes |                     Yes |
| Requires separate wrapper compilation |                   No |                   No |                        Yes |                     Yes |
| Suitable for private test exports     |        **Excellent** |            Excellent |                       Good |       Usually excessive |
| C declaration ergonomics              |  Manual Python types | **Natural C syntax** |           Natural C syntax | Interface/header driven |
| Compile-time signature checking       |                   No |                   No |                    **Yes** |                     Yes |
| Structures and pointers               |     Capable, verbose |       **Convenient** |                 Convenient |              Convenient |
| C++ support                           |           C ABI only |      C ABI preferred | C wrappers normally needed |           **Strongest** |
| Direct global-variable access         |                  Yes |                  Yes |                        Yes |                     Yes |
| Test-environment overhead             |           **Lowest** |                  Low |                   Moderate |                 Highest |
| Best role                             | Focused test harness |  Richer test harness |         Maintained binding |  Full binding generator |

For a small C or SQLite-extension project, the likely progression is:

```text
ctypes
    ↓ only if declarations become cumbersome
CFFI ABI mode
    ↓ only if compile-time checking or performance matters
CFFI API mode
```

SWIG is generally outside that progression unless the project evolves into a user-facing Python package.

---

### 1. Exporting C functions and variables from a DLL

Python cannot call a file-local `static` function or access a file-local `static` variable through a DLL. A target must have:

1. External linkage.
2. An exported DLL symbol on Windows.
3. A C-compatible name.
4. A known calling convention.
5. A Python declaration matching the binary interface exactly.

#### 1.1 A portable test-export macro

For test-only access, use one macro that changes both linkage and visibility:

```c_
#ifndef STAT_TEST_API_H
#define STAT_TEST_API_H

#if defined(SQLITE_TEST)

#  if defined(_WIN32)
#    define STAT_TEST_API __declspec(dllexport)
#  elif defined(__GNUC__) || defined(__clang__)
#    define STAT_TEST_API __attribute__((visibility("default")))
#  else
#    define STAT_TEST_API
#  endif

#else

#  define STAT_TEST_API static

#endif

#endif
```

Then define the routine normally:

```c
STAT_TEST_API sqlite3_int64
utf8_length(const char *z)
{
    /* implementation */
}
```

You do **not** need a separate declaration on the function when the complete definition already contains `STAT_TEST_API`.

In the production build this expands to:

```c
static sqlite3_int64 utf8_length(const char *z)
```

In the Windows test build it expands to:

```c
__declspec(dllexport) sqlite3_int64 utf8_length(const char *z)
```

This is a strong design for testing otherwise-private implementation routines because:

* production linkage remains private;
* no separate wrapper module is required;
* the implementation remains in exactly one place;
* the test DLL exposes only explicitly marked targets;
* pytest can test the same compiled implementation used by SQLite.

#### 1.2 Alternative separation of linkage and visibility

A more general macro pair can distinguish public linkage from DLL export:

```c
#if defined(SQLITE_TEST)
#  define STAT_TEST_LINKAGE
#  if defined(_WIN32)
#    define STAT_TEST_EXPORT __declspec(dllexport)
#  else
#    define STAT_TEST_EXPORT __attribute__((visibility("default")))
#  endif
#else
#  define STAT_TEST_LINKAGE static
#  define STAT_TEST_EXPORT
#endif

STAT_TEST_LINKAGE STAT_TEST_EXPORT sqlite3_int64
utf8_length(const char *z)
{
    /* implementation */
}
```

This is more explicit but usually unnecessary. A single prefix macro is simpler.

#### 1.3 C++ builds require `extern "C"`

If a source is compiled as C++, exported names are normally mangled. Python FFI libraries generally need a stable C symbol name:

```c_
#if defined(__cplusplus)
#  define STAT_EXTERN_C extern "C"
#else
#  define STAT_EXTERN_C
#endif

#if defined(SQLITE_TEST)
#  if defined(_WIN32)
#    define STAT_TEST_API STAT_EXTERN_C __declspec(dllexport)
#  else
#    define STAT_TEST_API \
        STAT_EXTERN_C __attribute__((visibility("default")))
#  endif
#else
#  define STAT_TEST_API static
#endif
```

For a source compiled as actual C, `extern "C"` is irrelevant.

#### 1.4 Calling convention

On 64-bit Windows, ordinary C calling conventions are effectively unified for the usual Python FFI use cases. On 32-bit Windows, `__cdecl` and `__stdcall` differ and must be matched.

A deliberately explicit macro is useful:

```c
#if defined(_WIN32)
###  define STAT_CALL __cdecl
#else
###  define STAT_CALL
#endif

STAT_TEST_API sqlite3_int64 STAT_CALL
utf8_length(const char *z)
{
    /* implementation */
}
```

With `ctypes`:

* `ctypes.CDLL` assumes the C calling convention;
* `ctypes.WinDLL` is for Windows API/`stdcall` functions.

Unless your code explicitly uses `__stdcall`, use `CDLL`.

#### 1.5 Exporting variables

A writable global variable can be exported:

```c
#if defined(SQLITE_TEST)
__declspec(dllexport)
int stat_test_counter = 0;
#else
static int stat_test_counter = 0;
#endif
```

A macro variant:

```c_
#if defined(SQLITE_TEST)
#  if defined(_WIN32)
#    define STAT_TEST_DATA __declspec(dllexport)
#  else
#    define STAT_TEST_DATA __attribute__((visibility("default")))
#  endif
#else
#  define STAT_TEST_DATA static
#endif

STAT_TEST_DATA int stat_test_counter = 0;
```

However, direct exported-data access is usually inferior to accessor functions.

Prefer:

```c
static int stat_test_counter = 0;

STAT_TEST_API int
stat_test_get_counter(void)
{
    return stat_test_counter;
}

STAT_TEST_API void
stat_test_set_counter(int value)
{
    stat_test_counter = value;
}
```

Accessor functions avoid several problems:

* accidental mutation from Python;
* exported-data semantics varying by toolchain;
* array and pointer ambiguity;
* thread-local storage complications;
* C ABI exposure of implementation details;
* difficulty changing the variable’s representation;
* inability to validate assigned values;
* confusing handling of `const` data;
* possible duplicate-storage behavior when import libraries are involved.

Export variables directly only where variable access itself is what you need to test.

#### 1.6 Inspecting DLL exports

On MSVC systems:

```cmd
dumpbin /exports path\to\sqlite3.dll
```

Check that the output contains the exact undecorated symbol:

```text
utf8_length
```

You may also produce an export map:

```cmd
dumpbin /exports path\to\sqlite3.dll > exports.txt
```

If the function is absent, common causes are:

* `SQLITE_TEST` was not defined;
* the function remained `static`;
* the source was not included in the DLL;
* the function was compiled as C++ and name-mangled;
* the macro was placed only on an unrelated declaration;
* link-time optimization removed or internalized the function;
* a `.def` file or visibility setting restricts exports;
* you inspected a stale DLL.

---

### 2. Testing with `ctypes`

#### 2.1 Why `ctypes` is the strongest default

`ctypes` is in the Python standard library. There is no generated code, binding build, package dependency, or wrapper-language layer.

The test project only needs:

```text
pytest
```

The DLL remains a normal native artifact. Python loads it dynamically.

The main discipline is that every function must be declared correctly in Python. An incorrect declaration can produce bad values, memory corruption, or a process crash.

#### 2.2 Basic function access

C:

```c
STAT_TEST_API int
add_ints(int a, int b)
{
    return a + b;
}
```

Python:

```python
import ctypes

dll = ctypes.CDLL(r"B:\project\build\sqlite3.dll")

dll.add_ints.argtypes = [ctypes.c_int, ctypes.c_int]
dll.add_ints.restype = ctypes.c_int

result = dll.add_ints(20, 22)
assert result == 42
```

Always set both `argtypes` and `restype`.

Without an explicit `restype`, `ctypes` assumes a C `int`. That is wrong for pointers, 64-bit integers, floating-point values, structures, and `void`.

For a `void` function:

```python
dll.reset_state.argtypes = []
dll.reset_state.restype = None
```

#### 2.3 Recommended pytest fixture

```python
from __future__ import annotations

import ctypes
from pathlib import Path

import pytest


DLL_PATH = (
    Path(__file__).resolve().parents[2]
    / "build"
    / "sqlite3.dll"
)


@pytest.fixture(scope="session")
def c_api() -> ctypes.CDLL:
    if not DLL_PATH.is_file():
        pytest.fail(f"Test DLL does not exist: {DLL_PATH}")

    try:
        dll = ctypes.CDLL(str(DLL_PATH))
    except OSError as exc:
        pytest.fail(f"Cannot load test DLL {DLL_PATH}: {exc}")

    dll.add_ints.argtypes = [ctypes.c_int, ctypes.c_int]
    dll.add_ints.restype = ctypes.c_int

    dll.utf8_length.argtypes = [ctypes.c_char_p]
    dll.utf8_length.restype = ctypes.c_int64

    return dll
```

Tests:

```python
import pytest


@pytest.mark.parametrize(
    ("a", "b", "expected"),
    [
        (0, 0, 0),
        (1, 2, 3),
        (-1, 1, 0),
        (-20, -22, -42),
    ],
)
def test_add_ints(c_api, a, b, expected):
    assert c_api.add_ints(a, b) == expected
```

Pytest fixtures provide explicit, reusable setup contexts, and parametrization is the natural mechanism for applying systematic input matrices to a native routine. ([pytest][3])

#### 2.4 Keep declarations out of `conftest.py` when they grow

For a few functions, fixture-local declarations are acceptable. For systematic testing, use a dedicated binding module:

```text
pytestenv/
├── pyproject.toml
├── src/
│   └── pytestenv/
│       ├── __init__.py
│       ├── native.py
│       └── types.py
└── tests/
    ├── conftest.py
    ├── test_utf8.py
    └── test_numeric.py
```

`native.py`:

```python
from __future__ import annotations

import ctypes
from pathlib import Path


class NativeAPI:
    def __init__(self, dll_path: Path) -> None:
        self.path = dll_path
        self.dll = ctypes.CDLL(str(dll_path))
        self._declare_functions()

    def _declare_functions(self) -> None:
        self.dll.utf8_length.argtypes = [ctypes.c_char_p]
        self.dll.utf8_length.restype = ctypes.c_int64

        self.dll.add_ints.argtypes = [
            ctypes.c_int,
            ctypes.c_int,
        ]
        self.dll.add_ints.restype = ctypes.c_int

    def utf8_length(self, text: str) -> int:
        encoded = text.encode("utf-8")
        return int(self.dll.utf8_length(encoded))
```

`conftest.py`:

```python
from pathlib import Path

import pytest

from pytestenv.native import NativeAPI


@pytest.fixture(scope="session")
def native_api() -> NativeAPI:
    dll_path = Path(__file__).resolve().parents[2] / "build" / "sqlite3.dll"
    if not dll_path.is_file():
        pytest.fail(f"Missing test DLL: {dll_path}")

    try:
        return NativeAPI(dll_path)
    except OSError as exc:
        pytest.fail(f"Failed to load {dll_path}: {exc}")
```

This prevents raw pointer and encoding details from leaking into every test.

#### 2.5 Integer type mapping

Typical mappings:

| C type               | `ctypes` type |
| -------------------- | ------------- |
| `char`               | `c_char`      |
| `signed char`        | `c_byte`      |
| `unsigned char`      | `c_ubyte`     |
| `short`              | `c_short`     |
| `unsigned short`     | `c_ushort`    |
| `int`                | `c_int`       |
| `unsigned int`       | `c_uint`      |
| `long`               | `c_long`      |
| `unsigned long`      | `c_ulong`     |
| `long long`          | `c_longlong`  |
| `unsigned long long` | `c_ulonglong` |
| `int8_t`             | `c_int8`      |
| `uint8_t`            | `c_uint8`     |
| `int16_t`            | `c_int16`     |
| `uint16_t`           | `c_uint16`    |
| `int32_t`            | `c_int32`     |
| `uint32_t`           | `c_uint32`    |
| `int64_t`            | `c_int64`     |
| `uint64_t`           | `c_uint64`    |
| `size_t`             | `c_size_t`    |
| `ptrdiff_t`          | `c_ssize_t`   |
| `_Bool`/`bool`       | `c_bool`      |
| `float`              | `c_float`     |
| `double`             | `c_double`    |
| `void` return        | `None`        |
| `void *`             | `c_void_p`    |

Do not assume C `long` is 64-bit. On 64-bit Windows it remains 32-bit. Fixed-width types are preferable at a DLL boundary.

For SQLite:

```python
sqlite3_int64 = ctypes.c_int64
sqlite3_uint64 = ctypes.c_uint64
```

#### 2.6 Strings

For:

```c
size_t utf8_length(const char *z);
```

use:

```python
dll.utf8_length.argtypes = [ctypes.c_char_p]
dll.utf8_length.restype = ctypes.c_size_t

result = dll.utf8_length("Русский".encode("utf-8"))
```

`c_char_p` is appropriate for NUL-terminated byte strings, not arbitrary binary buffers containing embedded zero bytes.

For a length-delimited buffer:

```c
size_t count_bytes(const unsigned char *data, size_t size);
```

use an array or pointer:

```python
dll.count_bytes.argtypes = [
    ctypes.POINTER(ctypes.c_ubyte),
    ctypes.c_size_t,
]
dll.count_bytes.restype = ctypes.c_size_t

payload = b"\x00\x01\x00\xff"
array = (ctypes.c_ubyte * len(payload)).from_buffer_copy(payload)

result = dll.count_bytes(array, len(payload))
```

#### 2.7 Output parameters

C:

```c
STAT_TEST_API int
parse_pair(const char *text, int *left, int *right);
```

Python:

```python
dll.parse_pair.argtypes = [
    ctypes.c_char_p,
    ctypes.POINTER(ctypes.c_int),
    ctypes.POINTER(ctypes.c_int),
]
dll.parse_pair.restype = ctypes.c_int

left = ctypes.c_int()
right = ctypes.c_int()

rc = dll.parse_pair(
    b"12,34",
    ctypes.byref(left),
    ctypes.byref(right),
)

assert rc == 0
assert left.value == 12
assert right.value == 34
```

#### 2.8 Arrays

C:

```c
STAT_TEST_API int64_t
sum_i32(const int32_t *values, size_t count);
```

Python:

```python
dll.sum_i32.argtypes = [
    ctypes.POINTER(ctypes.c_int32),
    ctypes.c_size_t,
]
dll.sum_i32.restype = ctypes.c_int64

values = [10, -3, 8]
array = (ctypes.c_int32 * len(values))(*values)

assert dll.sum_i32(array, len(values)) == 15
```

#### 2.9 Structures

C:

```c
typedef struct StatRange {
    int64_t minimum;
    int64_t maximum;
} StatRange;

STAT_TEST_API int
find_range(
    const int32_t *values,
    size_t count,
    StatRange *result
);
```

Python:

```python
class StatRange(ctypes.Structure):
    _fields_ = [
        ("minimum", ctypes.c_int64),
        ("maximum", ctypes.c_int64),
    ]


dll.find_range.argtypes = [
    ctypes.POINTER(ctypes.c_int32),
    ctypes.c_size_t,
    ctypes.POINTER(StatRange),
]
dll.find_range.restype = ctypes.c_int
```

Test:

```python
values = (ctypes.c_int32 * 3)(8, -4, 12)
result = StatRange()

rc = dll.find_range(values, 3, ctypes.byref(result))

assert rc == 0
assert result.minimum == -4
assert result.maximum == 12
```

Structure layout must match exactly:

* field order;
* field types;
* packing;
* alignment;
* architecture;
* conditional compilation;
* compiler ABI.

Avoid passing internal SQLite structures directly unless they are deliberately part of the test ABI.

#### 2.10 Returning structures

Small structures can be returned by value, but ABI rules are more sensitive. For test interfaces, prefer an output pointer:

```c
int calculate_result(Input input, Result *out);
```

instead of:

```c
Result calculate_result(Input input);
```

The output-pointer design also provides an explicit status code.

#### 2.11 Function pointers and callbacks

C:

```c
typedef int (*stat_predicate)(int value);

STAT_TEST_API int
count_matching(
    const int *values,
    size_t count,
    stat_predicate predicate
);
```

Python:

```python
PREDICATE = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_int)

dll.count_matching.argtypes = [
    ctypes.POINTER(ctypes.c_int),
    ctypes.c_size_t,
    PREDICATE,
]
dll.count_matching.restype = ctypes.c_int


@PREDICATE
def is_even(value):
    return int(value % 2 == 0)
```

Keep the callback object alive for the complete native call. A callback that is garbage-collected while C still retains its address can cause a crash.

Callbacks are possible with `ctypes`, but CFFI is often more comfortable when callbacks become numerous.

#### 2.12 Calling `malloc`-returning functions

Never allow Python to guess how returned memory should be freed.

Bad boundary:

```c
char *make_text(void);
```

Better boundary:

```c
STAT_TEST_API char *
make_text(void);

STAT_TEST_API void
free_text(char *text);
```

Python:

```python
dll.make_text.argtypes = []
dll.make_text.restype = ctypes.c_void_p

dll.free_text.argtypes = [ctypes.c_void_p]
dll.free_text.restype = None

address = dll.make_text()
try:
    assert address
    result = ctypes.string_at(address).decode("utf-8")
finally:
    dll.free_text(address)
```

Do not declare the return type as `c_char_p` if you must later free the original pointer. `c_char_p` can convert the result into Python bytes and obscure the ownership-bearing address.

For SQLite-owned allocations, export a corresponding test function that ultimately calls the same allocator’s deallocation routine, such as `sqlite3_free`, rather than using a different CRT’s `free`.

#### 2.13 Accessing exported variables with `ctypes`

C:

```c
STAT_TEST_DATA int stat_test_counter;
STAT_TEST_DATA uint64_t stat_test_mask;
```

Python:

```python
counter = ctypes.c_int.in_dll(dll, "stat_test_counter")
mask = ctypes.c_uint64.in_dll(dll, "stat_test_mask")

assert counter.value == 0
counter.value = 12
assert counter.value == 12
```

An exported array:

```c
STAT_TEST_DATA unsigned char stat_test_table[256];
```

Python:

```python
TableType = ctypes.c_ubyte * 256
table = TableType.in_dll(dll, "stat_test_table")

assert table[0] == 0
```

An exported pointer variable is not the same thing as an exported array:

```c
STAT_TEST_DATA const unsigned char *stat_test_table_ptr;
```

Python:

```python
pointer = ctypes.POINTER(ctypes.c_ubyte).in_dll(
    dll,
    "stat_test_table_ptr",
)
```

You must know whether the C symbol itself is:

* a scalar object;
* an array object;
* a pointer object;
* a pointer-to-pointer object.

All four have different binary representations.

#### 2.14 Error handling

`ctypes` does not turn arbitrary C status codes into exceptions. Wrap the raw API:

```python
class NativeError(RuntimeError):
    pass


def check_status(code: int, operation: str) -> None:
    if code != 0:
        raise NativeError(f"{operation} failed with status {code}")
```

Or attach an `errcheck` callback:

```python
def require_zero(result, function, arguments):
    if result != 0:
        raise NativeError(
            f"{function.__name__} failed with status {result}"
        )
    return result


dll.parse_pair.errcheck = require_zero
```

For unit tests, explicit status assertions are often preferable because they preserve the actual error result:

```python
assert dll.parse_pair(...) == STAT_ERROR_INVALID
```

#### 2.15 Crash behavior

A native access violation generally terminates the entire pytest process. Pytest cannot catch memory corruption as a normal Python exception.

For risky negative tests, use subprocess isolation:

```python
import subprocess
import sys


def test_invalid_pointer_is_rejected():
    result = subprocess.run(
        [
            sys.executable,
            "-m",
            "pytest",
            "-q",
            "tests/native_cases/test_invalid_pointer_case.py",
        ],
        check=False,
        capture_output=True,
        text=True,
    )

    assert result.returncode == 0, result.stdout + result.stderr
```

Better still, do not deliberately pass invalid pointers. Test invalid logical inputs—bad lengths, malformed byte sequences, out-of-range values—using valid memory objects.

---

### 3. Testing with CFFI

CFFI lets you write declarations in C-like syntax. It supports declarations for functions, types, constants, and global variables. In ABI mode, `ffi.dlopen()` returns a library object whose attributes expose the declarations supplied through `cdef()`. ([CFFI][1])

#### 3.1 CFFI ABI mode

This is the nearest CFFI equivalent to `ctypes`.

```python
from cffi import FFI

ffi = FFI()

ffi.cdef(
    """
    long long utf8_length(const char *z);
    int add_ints(int a, int b);
    extern int stat_test_counter;
    """
)

lib = ffi.dlopen(r"B:\project\build\sqlite3.dll")
```

Usage:

```python
assert lib.add_ints(20, 22) == 42
assert lib.utf8_length("Русский".encode("utf-8")) == 7

assert lib.stat_test_counter == 0
lib.stat_test_counter = 4
assert lib.stat_test_counter == 4
```

CFFI documentation explicitly supports reading and writing declared global variables through the loaded library object. ([CFFI][4])

##### Advantages over `ctypes`

* C declarations look like C.
* Pointer and structure syntax is usually easier to inspect.
* Allocation through `ffi.new()` is convenient.
* Casts and buffers are clearer.
* Header-derived declarations can be adapted more directly.
* Fewer repetitive `argtypes` assignments.

##### Disadvantages

* Third-party dependency.
* ABI mode is still based on declarations you supply manually.
* A wrong declaration can still crash.
* Preprocessor directives and arbitrary headers cannot simply be passed to `cdef()`.
* CFFI’s documentation recommends API mode where compiler-backed installation is acceptable because ABI mode is less checked and uses a general FFI call mechanism. ([CFFI][1])

#### 3.2 CFFI pytest fixture

```python
from pathlib import Path

import pytest
from cffi import FFI


@pytest.fixture(scope="session")
def c_api():
    dll_path = (
        Path(__file__).resolve().parents[2]
        / "build"
        / "sqlite3.dll"
    )

    if not dll_path.is_file():
        pytest.fail(f"Missing test DLL: {dll_path}")

    ffi = FFI()
    ffi.cdef(
        """
        typedef long long sqlite3_int64;

        sqlite3_int64 utf8_length(const char *z);
        int add_ints(int a, int b);
        """
    )

    try:
        lib = ffi.dlopen(str(dll_path))
    except OSError as exc:
        pytest.fail(f"Cannot load {dll_path}: {exc}")

    return ffi, lib
```

Test:

```python
import pytest


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("", 0),
        ("abc", 3),
        ("Русский", 7),
        ("AЯ", 2),
    ],
)
def test_utf8_length(c_api, text, expected):
    ffi, lib = c_api
    encoded = text.encode("utf-8")
    assert lib.utf8_length(encoded) == expected
```

#### 3.3 CFFI arrays and output parameters

C declarations:

```python
ffi.cdef(
    """
    typedef unsigned long long size_t;

    int find_range(
        const int *values,
        size_t count,
        long long *minimum,
        long long *maximum
    );
    """
)
```

Usage:

```python
values = ffi.new("int[]", [8, -4, 12])
minimum = ffi.new("long long *")
maximum = ffi.new("long long *")

rc = lib.find_range(
    values,
    3,
    minimum,
    maximum,
)

assert rc == 0
assert minimum[0] == -4
assert maximum[0] == 12
```

This is typically easier to read than the equivalent `ctypes.POINTER(...)` declarations.

#### 3.4 CFFI structures

```python
ffi.cdef(
    """
    typedef struct {
        long long minimum;
        long long maximum;
    } StatRange;

    int find_range(
        const int *values,
        size_t count,
        StatRange *result
    );
    """
)
```

Usage:

```python
values = ffi.new("int[]", [8, -4, 12])
result = ffi.new("StatRange *")

rc = lib.find_range(values, 3, result)

assert rc == 0
assert result.minimum == -4
assert result.maximum == 12
```

#### 3.5 Binary buffers

```python
data = b"\x00\x01\x00\xff"
buffer = ffi.from_buffer(data)

result = lib.count_bytes(
    ffi.cast("const unsigned char *", buffer),
    len(data),
)
```

You must retain the Python object and the CFFI buffer object for the period during which C accesses the memory.

#### 3.6 CFFI API mode

API mode creates a compiled Python extension. A build script might look like:

```python
from cffi import FFI

ffibuilder = FFI()

ffibuilder.cdef(
    """
    long long utf8_length(const char *z);
    int add_ints(int a, int b);
    """
)

ffibuilder.set_source(
    "pytestenv._native",
    """
    #include "stat_test_api.h"
    """,
    include_dirs=[r"B:\project\src"],
    libraries=["sqlite3"],
    library_dirs=[r"B:\project\build"],
)

if __name__ == "__main__":
    ffibuilder.compile(verbose=True)
```

Tests then use:

```python
from pytestenv._native import ffi, lib
```

API mode lets a C compiler verify declarations and can fill in certain C layout details. It also avoids the generic ABI-call path and can be substantially faster for large numbers of calls. ([CFFI][1])

For your test harness, these benefits probably do not offset:

* another generated extension;
* another build step;
* linker configuration;
* Python-version-specific `.pyd` artifacts;
* additional integration into the MSVC build workflow.

API mode becomes attractive if:

* each pytest run performs millions of tiny native calls;
* many structures require compiler-confirmed layouts;
* the test binding is becoming a maintained package;
* ABI declaration errors have become a recurring problem.

#### 3.7 CFFI and preprocessor-heavy headers

`cdef()` does not act as a full C preprocessor. In particular, arbitrary `#include` and conditional-compilation material is not accepted as though the string were a C translation unit. The declarations generally need to be reduced to the types, functions, constants, and globals required by Python. ([CFFI][1])

For a focused test API, maintain a compact declaration string rather than trying to parse the complete SQLite header surface.

---

### 4. Testing with SWIG

SWIG reads interface declarations and generates:

1. C or C++ wrapper source.
2. A compiled Python extension module.
3. Often a Python proxy module.

A minimal interface:

```swig
%module stat_test

%{
#include "stat_test_api.h"
%}

%include "stat_test_api.h"
```

Generation:

```cmd
swig -python -o stat_test_wrap.c stat_test.i
```

The generated wrapper must then be compiled and linked as a Python extension against:

* Python headers;
* Python import library on Windows;
* your C implementation or DLL import library.

SWIG’s Python documentation covers wrapper generation, Windows extension builds, functions, variables, pointers, structures, arrays, and C++ features. ([Swig][5])

#### 4.1 Calling functions

Given:

```c
int add_ints(int a, int b);
```

SWIG generally exposes:

```python
import stat_test

assert stat_test.add_ints(20, 22) == 42
```

This is pleasant once built. The cost is the wrapper-generation and extension-build pipeline.

#### 4.2 Accessing global variables

For:

```c
double threshold;
```

traditional SWIG Python bindings expose the global through `cvar`:

```python
import stat_test

stat_test.cvar.threshold = 0.75
assert stat_test.cvar.threshold == 0.75
```

SWIG documents this special `cvar` access model for Python globals. ([Swig][2])

#### 4.3 Typemaps

SWIG’s main power is its typemap system. Typemaps define conversions between C/C++ values and Python objects.

For example, a pointer-plus-length pair:

```c
int sum_values(const int *values, size_t count);
```

does not inherently tell SWIG that the pointer and length represent a Python sequence. A typemap can make this callable as:

```python
sum_values([1, 2, 3])
```

That is valuable for a public binding, but not necessarily for low-level tests. A test harness may benefit from exposing the exact native contract rather than hiding it behind conversions.

#### 4.4 Why SWIG is usually wrong for this task

For a small test API, SWIG adds:

* a separate interface file;
* generated wrapper C;
* Python development-header requirements;
* Python ABI/version coupling;
* another compiled `.pyd`;
* typemap design;
* generated-code diagnostics;
* wrapper rebuild dependencies;
* potential loss of visibility into the exact native boundary.

It is justified where the target API includes:

* many C++ classes;
* overloaded functions;
* inheritance;
* templates;
* substantial public-facing binding requirements;
* multiple target scripting languages.

It is not the simplest route for testing ten or twenty internal C routines.

---

### 5. Designing a test-only C ABI

The FFI library matters less than the quality of the test interface.

#### 5.1 Keep the interface flat

Prefer:

```c
int stat_parse_value(
    const unsigned char *input,
    size_t input_size,
    int64_t *result
);
```

over exposing a deeply nested internal context:

```c
int parse_value(
    ParseContext *context,
    TokenStream *tokens,
    ParseResult **result
);
```

A flat test ABI is easier to declare, test, fuzz, and keep stable.

#### 5.2 Use fixed-width scalar types

Prefer:

```c
int32_t
uint32_t
int64_t
uint64_t
size_t
double
```

Avoid ABI-ambiguous or compiler-dependent constructs where possible:

```c
long
enum-as-parameter
bit-fields
long double
wchar_t
```

Enums can be exposed as `int`, with named constants duplicated in Python or queried through exported accessor functions.

#### 5.3 Use pointer-plus-length for binary data

Prefer:

```c
int validate_utf8(
    const unsigned char *data,
    size_t size
);
```

not:

```c
int validate_utf8(const char *text);
```

when embedded NUL bytes are meaningful.

#### 5.4 Return status; write result through output parameters

A robust boundary:

```c
enum {
    STAT_OK = 0,
    STAT_ERROR_ARGUMENT = 1,
    STAT_ERROR_RANGE = 2,
    STAT_ERROR_ENCODING = 3
};

STAT_TEST_API int
stat_decode_integer(
    const unsigned char *data,
    size_t size,
    int64_t *result
);
```

This supports precise tests:

```python
assert api.decode_integer(b"123") == (STAT_OK, 123)
assert api.decode_integer(b"") == (STAT_ERROR_ARGUMENT, None)
assert api.decode_integer(b"abc") == (STAT_ERROR_ENCODING, None)
```

#### 5.5 Do not export entire internal state merely for assertions

Instead of exporting:

```c
ParserState parser_state;
```

export narrow observations:

```c
STAT_TEST_API int stat_test_get_token_count(void);
STAT_TEST_API int stat_test_get_error_offset(void);
STAT_TEST_API void stat_test_reset_state(void);
```

This preserves encapsulation and reduces ABI coupling.

#### 5.6 Test hooks should be deterministic

Useful hooks include:

```c
STAT_TEST_API void stat_test_reset(void);
STAT_TEST_API void stat_test_set_allocator_failure_after(int n);
STAT_TEST_API size_t stat_test_live_allocation_count(void);
STAT_TEST_API int stat_test_last_branch(void);
```

Such hooks can test difficult error paths without changing production behavior. They should exist only under the test-build macro.

#### 5.7 Avoid exposing SQLite callback entry points as unit-test targets

Functions receiving `sqlite3_context *` and `sqlite3_value **` are technically callable only with valid SQLite-created objects. Manually fabricating them through Python would be unsafe and would test an artificial environment.

Split code conceptually into:

```c
/* Logic routine: directly testable. */
static int decode_format(
    const unsigned char *input,
    size_t input_size,
    DecodeResult *result
);

/* SQLite adapter: tested through SQL. */
static void pblob_unpack_sql(
    sqlite3_context *context,
    int argc,
    sqlite3_value **argv
);
```

Under the test build:

```c
STAT_TEST_API int
decode_format(
    const unsigned char *input,
    size_t input_size,
    DecodeResult *result
);
```

Then:

* test `decode_format()` directly through `ctypes`;
* test `pblob_unpack_sql()` indirectly through SQL and Python’s `sqlite3` module.

That creates two complementary layers:

1. **Native logic unit tests** through DLL exports.
2. **SQLite integration tests** through SQL.

---

### 6. Suggested project architecture

```text
TOP/
├── pyproject.toml
├── src/
│   └── alphabet.c
├── pytestenv/
│   ├── src/
│   │   └── pytestenv/
│   │       ├── __init__.py
│   │       ├── native.py
│   │       ├── native_types.py
│   │       └── constants.py
│   └── tests/
│       ├── conftest.py
│       ├── native/
│       │   ├── test_utf8_length.py
│       │   ├── test_utf8_decode.py
│       │   └── test_range_logic.py
│       └── sql/
│           ├── test_registration.py
│           ├── test_alpha_string.py
│           └── test_errors.py
└── build/
    └── sqlite3.dll
```

Given your existing project arrangement, `constants.py` may instead be unnecessary: shared test constants can remain in an ordinary support module, while fixtures stay in `conftest.py`. The important rule is that tests import reusable Python modules through the installed `pytestenv` package, not by relying on implicit imports from the tests directory.

#### `native.py`

Responsibilities:

* locate and load the test DLL;
* declare function signatures once;
* expose safe Python methods;
* perform encoding;
* allocate input/output buffers;
* preserve pointer lifetimes;
* translate result structures into Python values;
* free native-owned results;
* optionally verify expected symbols at startup.

#### `conftest.py`

Responsibilities:

* session-scoped DLL/API fixture;
* SQLite connection fixtures;
* temporary database fixtures;
* automatic state reset where required;
* build-configuration validation.

#### Test modules

Tests should focus on:

* expected outputs;
* boundary values;
* malformed inputs;
* exact status codes;
* integer overflow boundaries;
* UTF-8 edge cases;
* empty inputs;
* embedded NULs;
* allocation-failure injection;
* deterministic state reset;
* production-vs-test build assumptions;
* SQL adapter behavior.

---

### 7. A robust `ctypes` implementation pattern

```python
from __future__ import annotations

import ctypes
from dataclasses import dataclass
from pathlib import Path


class NativeLibraryError(RuntimeError):
    pass


class DecodeResult(ctypes.Structure):
    _fields_ = [
        ("value", ctypes.c_int64),
        ("consumed", ctypes.c_size_t),
    ]


@dataclass(frozen=True)
class DecodedInteger:
    value: int
    consumed: int


class NativeAPI:
    def __init__(self, dll_path: Path) -> None:
        if not dll_path.is_file():
            raise NativeLibraryError(
                f"Native test library does not exist: {dll_path}"
            )

        try:
            self._dll = ctypes.CDLL(str(dll_path))
        except OSError as exc:
            raise NativeLibraryError(
                f"Could not load native test library {dll_path}: {exc}"
            ) from exc

        self._declare_api()

    def _declare_api(self) -> None:
        self._dll.stat_decode_integer.argtypes = [
            ctypes.POINTER(ctypes.c_ubyte),
            ctypes.c_size_t,
            ctypes.POINTER(DecodeResult),
        ]
        self._dll.stat_decode_integer.restype = ctypes.c_int

        self._dll.stat_test_reset.argtypes = []
        self._dll.stat_test_reset.restype = None

    def reset(self) -> None:
        self._dll.stat_test_reset()

    def decode_integer(
        self,
        data: bytes,
    ) -> tuple[int, DecodedInteger | None]:
        result = DecodeResult()

        if data:
            array = (
                ctypes.c_ubyte * len(data)
            ).from_buffer_copy(data)

            pointer = ctypes.cast(
                array,
                ctypes.POINTER(ctypes.c_ubyte),
            )
        else:
            array = None
            pointer = ctypes.POINTER(ctypes.c_ubyte)()

        status = int(
            self._dll.stat_decode_integer(
                pointer,
                len(data),
                ctypes.byref(result),
            )
        )

        if status != 0:
            return status, None

        return (
            status,
            DecodedInteger(
                value=int(result.value),
                consumed=int(result.consumed),
            ),
        )
```

Fixture:

```python
from pathlib import Path

import pytest

from pytestenv.native import NativeAPI


@pytest.fixture(scope="session")
def native_api() -> NativeAPI:
    path = Path(__file__).resolve().parents[2] / "build" / "sqlite3.dll"
    return NativeAPI(path)


@pytest.fixture(autouse=True)
def reset_native_state(native_api: NativeAPI) -> None:
    native_api.reset()
```

Tests:

```python
import pytest


STAT_OK = 0
STAT_ERROR_ARGUMENT = 1
STAT_ERROR_ENCODING = 2


@pytest.mark.parametrize(
    ("payload", "expected"),
    [
        (b"0", 0),
        (b"1", 1),
        (b"-1", -1),
        (b"9223372036854775807", 9223372036854775807),
        (b"-9223372036854775808", -9223372036854775808),
    ],
)
def test_decode_valid_integer(native_api, payload, expected):
    status, result = native_api.decode_integer(payload)

    assert status == STAT_OK
    assert result is not None
    assert result.value == expected
    assert result.consumed == len(payload)


@pytest.mark.parametrize(
    "payload",
    [
        b"",
        b"+",
        b"-",
        b"abc",
        b"12x",
        b"\x00",
    ],
)
def test_decode_rejects_invalid_input(native_api, payload):
    status, result = native_api.decode_integer(payload)

    assert status in {
        STAT_ERROR_ARGUMENT,
        STAT_ERROR_ENCODING,
    }
    assert result is None
```

This structure keeps the tests declarative. All FFI-specific complexity is concentrated in one adapter.

---

### 8. Build integration

For your SQLite amalgamation test build, the simplest model is:

```cmd
nmake /f Makefile.msc ^
  OPTS="-DSQLITE_TEST ..."
```

The exact variable used to carry compiler definitions depends on your build command and `Makefile.msc` integration, but the resulting C compilation must see:

```c
#define SQLITE_TEST 1
```

Your implementation then switches:

```c
#ifdef SQLITE_TEST
# if defined(_WIN32)
#  define STAT_TEST_API __declspec(dllexport)
# else
#  define STAT_TEST_API __attribute__((visibility("default")))
# endif
#else
# define STAT_TEST_API static
#endif
```

No wrapper source is needed.

No target routine must be duplicated.

No test runner is needed beyond pytest.

The artifact under test remains the actual `sqlite3.dll` test build containing the extension and the temporarily exported logic routines.

#### Recommended validation fixture

Export one build-marker function:

```c
STAT_TEST_API uint32_t
stat_test_abi_version(void)
{
    return UINT32_C(1);
}
```

Python:

```python
dll.stat_test_abi_version.argtypes = []
dll.stat_test_abi_version.restype = ctypes.c_uint32

version = dll.stat_test_abi_version()
if version != 1:
    raise NativeLibraryError(
        f"Unsupported test ABI version: {version}"
    )
```

This catches:

* accidentally loading the production DLL;
* loading an old test DLL;
* stale build directories;
* binding declarations that target a different interface revision.

You can also export a build fingerprint:

```c
STAT_TEST_API const char *
stat_test_build_id(void)
{
    return "alphabet-test-api/1";
}
```

Because this is static storage, Python may safely read it as `c_char_p`; Python does not free it.

---

### 9. What should and should not be exported

#### Good direct-test targets

Export routines that are:

* deterministic;
* independent of Python;
* independent of valid opaque SQLite objects;
* expressed through scalars, buffers, lengths, and simple result structures;
* responsible for parsing, conversion, validation, indexing, endianness, encoding, bounds, or numeric logic.

Examples:

```c
utf8_length
utf8_advance
utf8_decode_one
normalize_start
normalize_length
decode_float16
encode_float16
read_u32_le
read_u32_be
validate_format
calculate_output_size
```

#### Poor direct-test targets

Avoid directly exporting routines that:

* require `sqlite3_context *`;
* require `sqlite3_value **`;
* depend on an initialized SQLite connection;
* own complicated global state;
* expose internal allocator objects;
* return pointers into temporary stack storage;
* rely on undocumented structure layouts;
* are mere thin adapters around SQLite APIs.

Test these through SQL.

---

### 10. Final choice

For this project, I would use:

```text
pytest
    ├── Python sqlite3 module
    │     └── SQL-level integration tests
    │
    └── ctypes
          └── test-only exported C logic routines
```

The C source pattern:

```c
#ifdef SQLITE_TEST
# if defined(_WIN32)
#  define STAT_TEST_API __declspec(dllexport)
# else
#  define STAT_TEST_API __attribute__((visibility("default")))
# endif
#else
# define STAT_TEST_API static
#endif
```

The Python pattern:

```python
dll = ctypes.CDLL(str(dll_path))

dll.target.argtypes = [...]
dll.target.restype = ...
```

The pytest pattern:

```python
@pytest.fixture(scope="session")
def native_api():
    return NativeAPI(TEST_DLL)


@pytest.mark.parametrize(...)
def test_target(native_api, ...):
    ...
```

Choose CFFI ABI mode only when `ctypes` declarations become sufficiently verbose that C-like `cdef()` declarations materially improve maintainability. Choose CFFI API mode for a maintained compiler-checked binding, not as the initial test harness. Choose SWIG only if the goal changes from “test internal C logic” to “generate a substantial Python-facing C/C++ API.”

[1]: https://cffi.readthedocs.io/en/stable/overview.html "Overview — CFFI 2.1.0 documentation"
[2]: https://www.swig.org/Doc4.3/SWIGDocumentation.html "SWIG-4.3 Documentation"
[3]: https://docs.pytest.org/en/stable/how-to/parametrize.html "How to parametrize fixtures and test functions - pytest documentation"
[4]: https://cffi.readthedocs.io/en/latest/cdef.html "Preparing Wrapper Modules — CFFI 2.2.0.dev0 documentation"
[5]: https://www.swig.org/Doc4.3/Python.html "SWIG and Python"

---
---

## 📗 ctypes Autogen

> [!NOTE] Prompt
> 
> For ctypes, are there established active open tools automatically generating declarations from C signatures like CFFI?

Yes. The established options are **ctypesgen**, **ctypeslib2/clang2py**, and **PyCLibrary**. They differ significantly in how they parse C and what they generate.

### 1. ctypesgen

**ctypesgen** is the closest match to “take C headers and emit an importable `ctypes` module.”

It parses C headers, runs a C preprocessor, and generates Python containing:

* `ctypes.Structure` and `ctypes.Union` declarations;
* typedef mappings;
* function bindings;
* constants and enums;
* global-variable bindings;
* callback types;
* library-loading code.

A typical invocation is conceptually:

```cmd
ctypesgen ^
  --library sqlite3 ^
  --include "B:\project\src" ^
  "B:\project\src\stat_test_api.h" ^
  --output "pytestenv\src\pytestenv\_native_generated.py"
```

The generated module can then be imported by pytest:

```python
from pytestenv import _native_generated as native

assert native.utf8_length(b"abc") == 3
```

The project explicitly describes itself as an automatic generator of `ctypes` wrappers from C headers. It is also used in a current real-world binding-generation pipeline by pypdfium2, although that project uses its own ctypesgen fork for cleaner and more specialized output. ([PyPI][1])

#### Strengths

* Produces ordinary Python source.
* No compiled Python extension.
* Supports more than just function prototypes.
* Can process preprocessor definitions and included headers.
* Generated output can be inspected, committed, patched, or regenerated.
* Closest conceptual equivalent to CFFI’s C declarations while retaining `ctypes`.

#### Weaknesses

* Generated modules can be large and noisy.
* Real-world headers frequently require command-line defines, include paths, exclusions, or manual cleanup.
* Platform headers can cause enormous dependency expansion.
* Macros are inherently difficult to translate.
* Function ownership and higher-level semantics are not inferred.
* Generated library-loading logic may not match your desired DLL-location policy.

#### Suitability for your project

Potentially good, but probably more machinery than necessary when your test interface consists of perhaps 10–50 deliberately exported functions.

It becomes attractive when you maintain a dedicated, clean header such as:

```c
#ifndef ALPHABET_TEST_API_H
#define ALPHABET_TEST_API_H

#include <stddef.h>
#include <stdint.h>

int64_t utf8_length(const unsigned char *data, size_t size);

int utf8_decode_one(
    const unsigned char *data,
    size_t size,
    uint32_t *codepoint,
    size_t *consumed
);

#endif
```

It is much less attractive if pointed directly at `sqlite3.h`, internal SQLite headers, or the complete amalgamation.

---

### 2. ctypeslib2 and `clang2py`

**ctypeslib2** provides the `clang2py` generator. It uses **Clang’s parser**, rather than primarily relying on a custom C parser.

Its pipeline is approximately:

```text
C header
   ↓
Clang AST
   ↓
Python ctypes declarations
```

A typical command resembles:

```cmd
clang2py ^
  -o pytestenv\src\pytestenv\_native_generated.py ^
  -l B:\project\build\sqlite3.dll ^
  B:\project\src\alphabet_test_api.h
```

The project describes `clang2py` as using libclang’s Python bindings to parse declarations and generate `ctypes`-based Python code. ([PyPI][2])

#### Strengths

* Clang understands real C syntax and ABI-sensitive declarations better than lightweight parsers.
* Better foundation for:
    * anonymous structures and unions;
    * nested declarations;
    * attributes;
    * complex typedef chains;
    * architecture-specific layouts;
    * compiler-specific syntax.
* Can generate structures, unions, enums, typedefs, pointers, functions, and variables.
* Particularly useful when the test header is not trivially simple.

#### Weaknesses

* Requires a compatible Clang/libclang installation.
* Windows setup can be more involved than the actual bindings deserve.
* Correct Clang include paths and target options matter.
* Generated output may still need filtering or post-processing.
* Project release history and packaging have historically been less straightforward than mainstream Python packages.
* Parsing a large header graph can generate far more declarations than required.

#### Suitability for your project

Technically the strongest automatic generator among the traditional `ctypes` tools, especially where C declarations are complex.

For a small SQLite-extension test API, however, libclang may introduce more environmental complexity than manually writing:

```python
dll.utf8_length.argtypes = [
    ctypes.POINTER(ctypes.c_ubyte),
    ctypes.c_size_t,
]
dll.utf8_length.restype = ctypes.c_int64
```

It is most justified when the interface includes numerous structures, unions, callbacks, or platform-dependent layouts.

---

### 3. PyCLibrary

**PyCLibrary** takes a somewhat different approach. It contains:

1. A pure-Python C header parser.
2. A runtime library layer that uses parsed declarations to automate `ctypes` access.

Instead of necessarily generating a static Python source module, it can parse headers and bind functions through its `CLibrary` abstraction. Its documentation describes it as a C parser plus an automation library using header definitions to simplify C bindings; the currently implemented backend is based on `ctypes`. ([PyCLibrary][3])

Conceptually:

```python
from pyclibrary import CParser, CLibrary

parser = CParser(["alphabet_test_api.h"])
parser.process_all()

lib = CLibrary("sqlite3.dll", parser)
```

#### Strengths

* Can consume relatively raw C headers.
* Avoids manually duplicating every declaration in Python.
* Provides a higher-level runtime abstraction over `ctypes`.
* Supports parser caching.
* Useful for exploratory or dynamic binding workflows.

#### Weaknesses

* Adds its own runtime API between your tests and `ctypes`.
* Less explicit than a generated or handwritten binding module.
* Its custom parser cannot be expected to understand every MSVC or Clang language extension.
* Debugging a parser mismatch may be harder than debugging three explicit `argtypes` declarations.
* Less widely used than direct `ctypes`, CFFI, or SWIG.

#### Suitability for your project

Probably not the best fit. Your objective is a predictable pytest harness, not a generic dynamic C-library browser.

For testing, explicit generated Python source is preferable to reparsing headers at test startup.

---

### Other relevant tools

#### pyglet `wraptypes`

pyglet contains an internal header-to-`ctypes` wrapper generator named `wraptypes`. Its documentation calls it a utility for creating `ctypes` wrappers from C header files. ([Pyglet Documentation][4])

It is actively used inside the pyglet ecosystem, but it is primarily an internal project tool rather than the default general-purpose recommendation for an independent test harness.

#### Project-specific generators

Several substantial projects maintain custom or forked generators. pypdfium2, for example, uses a fork of ctypesgen because it requires cleaner output and project-specific behavior. ([GitHub][5])

This illustrates an important reality: automatic generation works well for low-level declarations, but mature projects frequently add:

* symbol allowlists;
* custom DLL loading;
* type overrides;
* post-processing;
* platform guards;
* generated-code normalization.

---

### Comparison

| Tool                  | Parsing approach           | Output model                | External compiler/parser | Best use                           |
| --------------------- | -------------------------- | --------------------------- | ------------------------ | ---------------------------------- |
| ctypesgen             | Preprocessor plus C parser | Generated Python module     | C preprocessor           | Clean ordinary C headers           |
| ctypeslib2 / clang2py | Clang AST                  | Generated Python module     | Clang/libclang           | Complex or ABI-sensitive headers   |
| PyCLibrary            | Pure-Python parser         | Runtime binding abstraction | Normally none            | Dynamic/exploratory header binding |
| pyglet wraptypes      | Custom parser/generator    | Generated Python module     | Tool-specific            | Mostly pyglet ecosystem            |

### Recommendation for your pytest harness

I would **not initially add a general-purpose declaration generator**.

Your test API should be deliberately small and flat. For example:

```c
STAT_TEST_API sqlite3_int64
utf8_length(const unsigned char *data, size_t size);

STAT_TEST_API int
utf8_decode_one(
    const unsigned char *data,
    size_t size,
    uint32_t *codepoint,
    size_t *consumed
);
```

The corresponding manual declarations require only a few lines:

```python
dll.utf8_length.argtypes = [
    ctypes.POINTER(ctypes.c_ubyte),
    ctypes.c_size_t,
]
dll.utf8_length.restype = ctypes.c_int64

dll.utf8_decode_one.argtypes = [
    ctypes.POINTER(ctypes.c_ubyte),
    ctypes.c_size_t,
    ctypes.POINTER(ctypes.c_uint32),
    ctypes.POINTER(ctypes.c_size_t),
]
dll.utf8_decode_one.restype = ctypes.c_int
```

This manual layer has useful properties:

* exact and reviewable;
* no Clang dependency;
* no parser inconsistencies;
* no generated noise;
* no accidental exposure of unrelated symbols;
* trivial to integrate with pytest;
* easy to wrap with safe Python methods.

### When generation becomes worthwhile

Adopt **ctypesgen** when:

* the test API reaches dozens or hundreds of declarations;
* declarations change frequently;
* repetitive manual synchronization becomes a real maintenance burden;
* structures and callback typedefs dominate the interface.

Adopt **clang2py** when:

* structures are complex;
* anonymous unions or compiler attributes matter;
* MSVC layout compatibility must be reproduced;
* ordinary header parsers fail.

For your present design, a particularly effective compromise is to generate only from a dedicated test API header:

```text
src/alphabet.c
tests/native/alphabet_test_api.h
pytestenv/src/pytestenv/_native_generated.py
```

Do not generate from `sqlite3.h` or `sqlite3.c`. Restrict the generator to a compact declaration surface containing only the test-exported functions and types.

Between the available tools, **ctypesgen is the simplest first experiment**, while **clang2py is the more technically rigorous parser-based option**. For a small test interface, handwritten `ctypes` declarations remain simpler and more robust than either.

[1]: https://pypi.org/project/ctypesgen/ "ctypesgen · PyPI"
[2]: https://pypi.org/project/ctypeslib2/2.0/ "ctypeslib2 · PyPI"
[3]: https://pyclibrary.readthedocs.io/ "Welcome to PyCLibrary’s documentation! — PyCLibrary 0.2.0.dev documentation"
[4]: https://pyglet.readthedocs.io/en/latest/internal/wraptypes.html "wraptypes — pyglet v2.1.14"
[5]: https://github.com/pypdfium2-team "pypdfium2-team · GitHub"

---
---

## 📗 C Header Generation

> [!NOTE] Prompt
> 
> Tell me about leading active open tools for generating*.h

Assuming you mean **generating a `.h` header from function definitions in one or more `.c` files**, the field is surprisingly small. There is one clear turnkey leader, followed by compiler-based building blocks that require some scripting.

### 1. `cproto` — the leading dedicated tool

**`cproto` is the most established purpose-built tool for extracting C function prototypes and variable declarations from C source.**

It can:

* scan `.c` files;
* emit prototypes for function definitions;
* optionally emit declarations for global variables;
* process included project files;
* handle both modern ANSI C definitions and older K&R syntax;
* write output suitable for incorporation into a header.

It remains actively maintained and packaged in current Debian and BSD distributions. The latest packaging activity in 2026 identifies the current 4.7/4.8 line. ([Debian Manpages][1])

Basic use:

```cmd
cproto alphabet.c > alphabet_generated.h
```

Multiple sources:

```cmd
cproto source1.c source2.c source3.c > internal_test_api.h
```

It can also emit variables:

```cmd
cproto -v alphabet.c > alphabet_generated.h
```

The exact option spelling should be checked against the installed version because `cproto` has a fairly extensive historical option set.

#### What it generates

Given:

```c
static sqlite3_int64
utf8_length(const char *z)
{
    /* ... */
}

int
decode_utf8(
    const unsigned char *data,
    size_t size,
    uint32_t *codepoint
)
{
    /* ... */
}
```

the extracted content is approximately:

```c
static sqlite3_int64 utf8_length(const char *z);

int decode_utf8(
    const unsigned char *data,
    size_t size,
    uint32_t *codepoint
);
```

You would normally filter or transform this further because a test header probably should not preserve `static`.

#### Strengths

* Dedicated exactly to this problem.
* Mature parser rather than regex extraction.
* Very small operational footprint.
* Produces plain C declarations.
* Works naturally in a build script.
* No Python dependency.
* Public-domain core licensing.
* Better suited to ordinary C than heavyweight Clang tooling.

#### Limitations

`cproto` extracts declarations; it does not understand your architectural intent.

It cannot inherently know:

* which functions belong in the test API;
* which `static` functions should become test exports;
* which macros should decorate declarations;
* whether a declaration should use `STAT_TEST_API`;
* whether a variable should be exposed directly or through accessors;
* which declarations are implementation details;
* what header guard to use;
* which supporting typedefs and includes are required;
* whether the generated header remains ABI-safe.

It is therefore best used as an **extraction engine**, followed by controlled filtering or post-processing.

#### Assessment

For a small C99 project on Windows where you want a simple generated test header, this is the first tool I would evaluate.

---

### 2. CProtoGen — modern lightweight Python alternative

**CProtoGen** is a newer Python package and CLI specifically for generating C function prototypes from source files. It can create or overwrite a corresponding header and add conventional header scaffolding. ([PyPI][2])

Typical use:

```cmd
python -m pip install cprotogen

cprotogen src\alphabet.c ^
  --header tests\native\alphabet_test_api.h ^
  --overwrite
```

Programmatic use:

```python
from cprotogen.generator import generate_prototypes

generate_prototypes(
    "src/alphabet.c",
    "tests/native/alphabet_test_api.h",
    overwrite=True,
)
```

#### Strengths

* Native Windows/Python workflow.
* Easy to integrate into your pytest environment.
* Can directly create a `.h` file rather than merely writing declarations to stdout.
* Small and understandable implementation.
* MIT licensed.
* Convenient where the entire project already depends on Python.

#### Limitations

It is much younger and less battle-tested than `cproto`.

For serious C parsing, examine how it handles:

* conditional compilation;
* macros in return types;
* function-pointer parameters;
* multiline attributes;
* MSVC declarations;
* nested preprocessor branches;
* comments between declarator components;
* complex array parameters;
* typedef-dependent signatures;
* definitions embedded in SQLite amalgamation-style code.

I would not assume it has compiler-grade parsing without validating it against your actual source.

#### Assessment

Attractive for simple signatures, but `cproto` is the safer established choice.

---

### 3. Clang LibTooling and AST Matchers — strongest foundation for a custom generator

Clang does not ship a standard command called “generate this project’s public header,” but it provides the strongest open infrastructure for building one:

* Clang parser and semantic analysis;
* LibTooling;
* AST Matchers;
* source locations and source ranges;
* canonical and written types;
* access to attributes, linkage, storage class, and declarations;
* compilation database support.

Clang’s LibTooling is explicitly intended for standalone source-analysis and source-transformation tools, while AST Matchers provide structured matching of functions, variables, records, and other declaration nodes. ([Clang][3])

A custom matcher can select only function definitions satisfying your rules:

```cpp
functionDecl(
    isDefinition(),
    isExpansionInMainFile()
).bind("function")
```

Your generator can then emit:

```c
STAT_TEST_API sqlite3_int64
utf8_length(const char *z);
```

rather than blindly reproducing:

```c
static sqlite3_int64
utf8_length(const char *z);
```

#### Why this is technically superior

A Clang-based generator can understand:

* actual C grammar;
* macro-expanded versus written declarations;
* storage class;
* external versus internal linkage;
* calling conventions;
* compiler attributes;
* typedef chains;
* function-pointer parameters;
* anonymous structures and unions;
* target-specific type sizes;
* source-file ownership;
* conditional compilation under the exact test-build flags.

It can also use the real compiler command:

```text
cl.exe /DSQLITE_TEST /I... /D...
```

through a compilation database or explicitly supplied options.

#### Cost

This is not a turnkey low-overhead solution.

You must implement and maintain:

* symbol-selection rules;
* declaration rendering;
* macro policy;
* ordering;
* dependency discovery for typedefs;
* includes;
* header guards;
* deterministic output;
* duplicate removal.

LibTooling also normally means writing and building a C++ utility against LLVM/Clang.

#### Assessment

Use this only when automated header generation becomes a real subsystem. It is excessive for extracting ten test functions.

---

### 4. Python with `libclang` bindings

A lighter variant of Clang tooling is a Python script using Clang’s Python bindings.

Conceptually:

```python
from clang.cindex import CursorKind, Index

index = Index.create()
translation_unit = index.parse(
    "src/alphabet.c",
    args=[
        "-DSQLITE_TEST",
        "-Isqlite",
    ],
)

for cursor in translation_unit.cursor.walk_preorder():
    if cursor.kind == CursorKind.FUNCTION_DECL:
        if cursor.is_definition():
            print(cursor.spelling)
```

The script can inspect:

* return types;
* parameter types;
* storage class;
* source location;
* linkage;
* annotations or attributes.

#### Strengths

* Compiler-grade parsing.
* Easier to prototype than a C++ LibTooling utility.
* Natural fit in a Python-driven test project.
* Easy to combine with explicit allowlists or source annotations.
* Output can be deterministic and narrowly tailored.

#### Weaknesses

* Requires Clang and compatible Python bindings.
* The Python bindings expose less than the full C++ Clang API.
* Reconstructing declarations exactly can be difficult.
* MSVC compatibility requires correct target and include settings.
* You still have to design the header generator.

#### Assessment

This is probably the best foundation if you eventually want a custom robust generator but do not want to implement it in C++.

---

### 5. CastXML — robust AST interchange, not a direct header generator

**CastXML** is an actively maintained Kitware project that uses Clang to produce an XML representation of C-family declarations. Its latest release was in February 2026, and it explicitly supports emulating both GNU and MSVC compiler environments. ([GitHub][4])

Example:

```cmd
castxml ^
  --castxml-cc-msvc "cl.exe" ^
  src\alphabet.c ^
  -o alphabet.xml
```

You then write a second-stage generator that reads the XML and emits a header.

#### Strengths

* Clang-grade parsing.
* Structured, language-neutral output.
* Explicit MSVC mode.
* Maintained and cross-platform.
* Useful if several downstream generators need the same parsed API.
* Avoids linking your own utility directly against Clang libraries.

#### Weaknesses

* Does not itself emit `.h`.
* XML is verbose.
* Requires custom transformation logic.
* More moving parts than direct AST scripting.
* Primarily designed around declaration extraction from headers and binding-generation workflows, rather than synthesizing headers from implementation files.

#### Assessment

A good intermediate representation for a substantial binding generator, but unnecessary for a focused pytest test header.

---

### 6. GCC `-aux-info`

GCC has a compiler option called `-aux-info` that writes declaration information gathered while compiling a translation unit. Historically this supported GCC’s `protoize` workflow. GCC documentation describes generating `.X` files containing prototype information with:

```sh
gcc -Dfoo=bar file1.c -aux-info file1.X
```

([GCC][5])

Conceptually:

```cmd
gcc -c src\alphabet.c ^
  -aux-info build\alphabet.X ^
  -o build\alphabet.o
```

The `.X` file contains declarations for functions encountered by the compiler.

#### Strengths

* Uses the real compiler parser.
* Sees the source under actual preprocessor definitions.
* No separate parser.
* Can be incorporated into GCC/MinGW builds.

#### Weaknesses

* GCC-specific.
* Output is auxiliary compiler data, not a polished header.
* Not useful for your primary MSVC build unless you additionally parse with GCC.
* It may encode declarations in a format intended for GCC tooling rather than stable public consumption.
* Does not solve export macro insertion or API selection.

#### Assessment

Interesting for MinGW pipelines, but not appropriate as the primary solution for your MSVC-oriented test environment.

---

### 7. Doxygen XML — possible but indirect

Doxygen can parse C and emit structured XML describing functions, variables, types, enums, and macros. Its current project remains actively developed, with a 2026 release. ([GitHub][6])

Configuration:

```text
GENERATE_XML = YES
EXTRACT_ALL = YES
INPUT = src
```

You could transform Doxygen XML into a header.

#### Strengths

* Mature and actively maintained.
* Already useful for documentation.
* Handles documented public APIs particularly well.
* XML output is designed for downstream processing.
* Can preserve descriptions alongside declarations.

#### Weaknesses

* Documentation parser, not a compiler frontend.
* Not intended to reproduce ABI declarations exactly.
* Macro-heavy code can require careful configuration.
* Requires a custom XML-to-header stage.
* Inferior to Clang when correctness of complex C declarators matters.

#### Assessment

Reasonable only when Doxygen is already authoritative for API metadata. Do not adopt it solely to generate a test header.

---

### 8. Tools that should not be treated as robust solutions

#### Regex-based IDE extensions

There are editor extensions that claim to generate `.h` files from `.c` or `.cpp` using regex extraction. One current VS Code extension explicitly advertises regex-based handling of functions, classes, structures, enums, typedefs, and macros. ([Visual Studio Marketplace][7])

These can be convenient interactively, but they are unsuitable as a trustworthy build component.

Regex generally breaks on valid constructs such as:

```c
int
(*make_callback(
    int mode
))(const unsigned char *, size_t);
```

or:

```c
STAT_TEST_API
sqlite3_int64
utf8_length(
    const char *z
)
{
    /* ... */
}
```

or declarations controlled by nested preprocessing.

#### Ctags

Universal Ctags is excellent for locating symbols but does not preserve enough complete type and declarator information to generate an ABI-correct header reliably.

#### Doxygen alone

Doxygen generates documentation, not source headers. Its XML can feed a custom generator, but it should not be described as a direct `.h` generator.

---

### The key architectural problem

Automatically generating a header from implementation definitions reverses the conventional C dependency direction.

The conventional model is:

```text
header declaration
        ↓
implementation includes header
        ↓
compiler verifies definition matches declaration
```

For example:

```c
/* alphabet_test_api.h */

STAT_TEST_API sqlite3_int64
utf8_length(const char *z);
```

```c
/* alphabet.c */

#include "alphabet_test_api.h"

STAT_TEST_API sqlite3_int64
utf8_length(const char *z)
{
    /* ... */
}
```

This gives compiler-enforced consistency.

The generated-header model is:

```text
implementation definition
        ↓
generator parses implementation
        ↓
header is produced
        ↓
Python declaration generator consumes header
```

This avoids duplicate manual declarations, but introduces:

* generator dependency;
* symbol-selection policy;
* generated-file lifecycle;
* risk of stale generated output;
* potential parser disagreement with MSVC;
* test ABI accidentally changing whenever an implementation signature changes.

For production APIs, hand-maintained headers are normally preferable. For a **test-only export surface**, generated headers are more defensible because the header is tooling input rather than a stable public API.

### Best design for your specific purpose

Your source definitions could be annotated with a test-export macro:

```c
STAT_TEST_API sqlite3_int64
utf8_length(const char *z)
{
    /* ... */
}

STAT_TEST_API int
utf8_decode_one(
    const unsigned char *z,
    size_t n,
    uint32_t *codepoint,
    size_t *consumed
)
{
    /* ... */
}
```

Production:

```c
#define STAT_TEST_API static
```

Test build:

```c
#define STAT_TEST_API __declspec(dllexport)
```

A generator should extract **only definitions carrying `STAT_TEST_API`**.

The generated header should contain:

```c
#ifndef ALPHABET_TEST_API_H
#define ALPHABET_TEST_API_H

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
# define STAT_TEST_DECL __declspec(dllimport)
#else
# define STAT_TEST_DECL
#endif

STAT_TEST_DECL sqlite3_int64
utf8_length(const char *z);

STAT_TEST_DECL int
utf8_decode_one(
    const unsigned char *z,
    size_t n,
    uint32_t *codepoint,
    size_t *consumed
);

#endif
```

Note that the consuming header normally needs `dllimport`, not `dllexport`, although neither is needed merely for parsing it into `ctypes` declarations.

### Practical ranking

| Tool              |   Turnkey `.c` → prototypes |            Parser quality |                Windows/MSVC fit |                Customization | Recommendation           |
| ----------------- | --------------------------: | ------------------------: | ------------------------------: | ---------------------------: | ------------------------ |
| `cproto`          |                     **Yes** | Good traditional C parser |                        Moderate | Moderate via post-processing | **Best initial tool**    |
| CProtoGen         |                         Yes |    Suitable for simpler C |                        **Easy** |      Easy Python integration | Worth evaluating         |
| Python `libclang` |         No, script required |        **Compiler-grade** | Good with correct configuration |                **Excellent** | Best custom route        |
| Clang LibTooling  | No, implementation required |        **Compiler-grade** |                            Good |                  **Maximum** | For mature tooling       |
| CastXML           |       Intermediate XML only |            Compiler-grade |       **Explicit MSVC support** |                         High | For larger generators    |
| GCC `-aux-info`   |              Prototype data |            Compiler-grade |          Poor for MSVC workflow |                          Low | Not recommended here     |
| Doxygen XML       |            Intermediate XML |       Documentation-grade |                            Good |                         High | Only if already used     |
| Regex extensions  |                         Yes |                      Weak |                            Easy |                          Low | Not for automated builds |

### Recommendation

For your current project:

1. Try **`cproto`** against the actual module and inspect its handling of `STAT_TEST_API`, multiline signatures, SQLite types, and preprocessor branches.
2. Put an explicit marker on every test-visible definition.
3. Filter the extracted output so only marked functions enter the generated header.
4. Add deterministic header guards and required includes in a small Python or Tcl postprocessor.
5. Feed that compact generated header into a separate `ctypes` declaration generator—or generate the `ctypes` declarations directly from the same extraction stage.

The more direct long-term design is actually:

```text
annotated C definitions
        ↓
Clang-based generator
        ├── generated test_api.h
        └── generated _ctypes.py
```

Generating both outputs from the same AST avoids an unnecessary intermediate parsing cycle. For a first implementation, though, **`cproto` plus a small deterministic postprocessor is the lowest-overhead credible route**.

[1]: https://manpages.debian.org/trixie/cproto/cproto.1.en.html "cproto(1) — cproto — Debian trixie — Debian Manpages"
[2]: https://pypi.org/project/cprotogen/ "cprotogen · PyPI"
[3]: https://clang.llvm.org/docs/LibASTMatchersTutorial.html "Tutorial for building tools using LibTooling and LibASTMatchers — Clang 24.0.0git documentation"
[4]: https://github.com/CastXML/CastXML "GitHub - CastXML/CastXML: C-family Abstract Syntax Tree XML Output · GitHub"
[5]: https://gcc.gnu.org/onlinedocs/gcc-3.2.3/gcc/Running-Protoize.html "Using the GNU Compiler Collection (GCC)"
[6]: https://github.com/doxygen/doxygen "GitHub - doxygen/doxygen: Official doxygen git repository · GitHub"
[7]: https://marketplace.visualstudio.com/items?itemName=KairavDutta.header-file-generator "Header File Generator - Visual Studio Marketplace"

---
---

## 📗 Python LibClang

> [!NOTE] Prompt
> 
> I have installed
> `mamba install -c conda-forge clang clangdev libclang clang-tools`
> and I have active MSVC setup.
> Is this enough for Python libclang?

**Almost.** You have the Clang compiler, development files, `libclang.dll`, and command-line tools, but the Python bindings are normally supplied by the separate conda-forge package **`python-clang`**. ([Anaconda][1])

Install it in the same environment:

```cmd
mamba install -c conda-forge python-clang
```

Your complete installation is therefore:

```cmd
mamba install -c conda-forge ^
  clang clangdev libclang clang-tools python-clang
```

### Verify the installation

Run:

```cmd
python -c "from clang import cindex; print(cindex.__file__)"
```

Then test whether the binding can load `libclang.dll` and create an index:

```cmd
python -c "from clang.cindex import Index; print(Index.create())"
```

If both commands succeed, the Python binding is operational. Clang’s Python interface is built over libclang, Clang’s relatively stable C API. ([Clang][2])

### Minimal parsing test

Create `test.c`:

```c
static int add(int a, int b)
{
    return a + b;
}
```

Then run:

```python
from clang.cindex import CursorKind, Index

index = Index.create()

translation_unit = index.parse(
    "test.c",
    args=["-std=c11"],
)

for diagnostic in translation_unit.diagnostics:
    print(diagnostic)

for cursor in translation_unit.cursor.get_children():
    if cursor.kind == CursorKind.FUNCTION_DECL:
        print(
            cursor.spelling,
            cursor.result_type.spelling,
            cursor.is_definition(),
        )
```

Expected output should include something resembling:

```text
add int True
```

### If Python cannot find `libclang.dll`

On a conda-forge Windows environment, it is commonly located under:

```text
%CONDA_PREFIX%\Library\bin\libclang.dll
```

Verify:

```cmd
where libclang.dll
dir "%CONDA_PREFIX%\Library\bin\libclang.dll"
```

Then configure it explicitly before creating an `Index`:

```python
from pathlib import Path
import os

from clang.cindex import Config, Index

libclang_path = (
    Path(os.environ["CONDA_PREFIX"])
    / "Library"
    / "bin"
    / "libclang.dll"
)

Config.set_library_file(str(libclang_path))

index = Index.create()
```

The configuration must occur before the first operation that loads libclang.

A reusable setup function:

```python
from __future__ import annotations

import os
from pathlib import Path

from clang.cindex import Config


def configure_libclang() -> Path:
    conda_prefix = os.environ.get("CONDA_PREFIX")
    if not conda_prefix:
        raise RuntimeError("CONDA_PREFIX is not defined")

    library = (
        Path(conda_prefix)
        / "Library"
        / "bin"
        / "libclang.dll"
    )

    if not library.is_file():
        raise FileNotFoundError(f"libclang.dll not found: {library}")

    Config.set_library_file(str(library))
    return library
```

### Version compatibility

The Python `clang.cindex` package and `libclang.dll` should come from the **same LLVM/Clang release line**. Installing both from the same conda-forge environment normally gives the solver an opportunity to select compatible builds.

Inspect installed packages:

```cmd
mamba list | findstr /i "clang llvm"
```

You should see mutually compatible versions for at least:

```text
clang
clangdev
libclang
python-clang
```

A mismatch often produces errors such as:

```text
undefined symbol
```

or:

```text
function ... not found
```

when `clang.cindex` attempts to bind functions exported by `libclang.dll`.

### MSVC setup and parsing

Having an active MSVC developer environment helps because you have variables such as:

```text
INCLUDE
LIB
PATH
VCToolsInstallDir
WindowsSdkDir
```

However, libclang does not automatically become MSVC merely because `cl.exe` is available. When parsing a translation unit, you still need to provide the relevant compilation arguments.

For ordinary self-contained C:

```python
translation_unit = index.parse(
    "src/alphabet.c",
    args=[
        "-x",
        "c",
        "-std=c11",
        "-DSQLITE_TEST=1",
        "-Isrc",
        "-Ibuild/sqlite",
    ],
)
```

For source using Microsoft extensions:

```python
translation_unit = index.parse(
    "src/alphabet.c",
    args=[
        "-x",
        "c",
        "-std=c11",
        "-fms-extensions",
        "-fms-compatibility",
        "-DSQLITE_TEST=1",
        "-Isrc",
        "-Ibuild/sqlite",
    ],
)
```

Clang accepts most `cl.exe` language constructs, but its parser arguments use Clang-style options unless you invoke a driver explicitly in `clang-cl` mode.

### Do you need all four existing packages?

For a Python libclang script:

| Package        |              Needed? | Purpose                                         |
| -------------- | -------------------: | ----------------------------------------------- |
| `libclang`     |              **Yes** | `libclang.dll`, the C API loaded by Python      |
| `python-clang` |              **Yes** | `clang.cindex` Python module                    |
| `clang`        |               Useful | Compiler driver and associated runtime          |
| `clangdev`     | Usually not required | Development headers and libraries               |
| `clang-tools`  |         Not required | `clang-format`, `clang-tidy`, and related tools |

The minimal installation is generally:

```cmd
mamba install -c conda-forge libclang python-clang
```

For your intended AST/header-generation work, keeping the complete toolchain is reasonable.

### One-command definitive check

After installing `python-clang`:

```cmd
python -c "import os; from pathlib import Path; from clang.cindex import Config,Index; p=Path(os.environ['CONDA_PREFIX'])/'Library'/'bin'/'libclang.dll'; Config.set_library_file(str(p)); print('libclang:',p); print('index:',Index.create())"
```

If that succeeds, your environment is sufficient for developing a Python-based Clang AST extractor.

[1]: https://anaconda.org/conda-forge/libclang/ "libclang - conda-forge | Anaconda.org"
[2]: https://clang.llvm.org/docs/LibClang.html "Libclang tutorial — Clang 24.0.0git documentation"

---
---

## 📗 Generating C Headers and `ctypes` Definitions

> [!NOTE] Prompt
> 
> Minimal parsing test works. How do I proceed to creating a C header? Now that parser works, can I use results to also create \*.py ctypes definitions module?

Yes. Once `libclang` parsing works, you can generate both:

```text
annotated C definitions
        ↓
libclang AST extractor
        ↓
shared intermediate model
        ├── generated_test_api.h
        └── generated_ctypes.py
```

This is preferable to generating a header and then reparsing that header for `ctypes`: both outputs come from the same parsed translation unit and therefore cannot drift independently.

Libclang exposes AST traversal, cursor types, source ranges, linkage, storage classes, argument cursors, type spellings, and source tokenization. However, it is intentionally a relatively small, stable interface rather than complete access to every detail in Clang’s internal C++ AST. ([Clang][1])

### 1. Mark test-exported functions explicitly

Use a marker macro on each function that should enter the generated test API:

```c_
#ifdef SQLITE_TEST
# if defined(_WIN32)
#  define STAT_TEST_API __declspec(dllexport)
# else
#  define STAT_TEST_API __attribute__((visibility("default")))
# endif
#else
# define STAT_TEST_API static
#endif
```

Definitions:

```c
STAT_TEST_API sqlite3_int64
utf8_length(const char *z)
{
    /* ... */
}

STAT_TEST_API int
utf8_decode_one(
    const unsigned char *z,
    size_t n,
    uint32_t *codepoint,
    size_t *consumed
)
{
    /* ... */
}
```

The generator should select only definitions whose source spelling contains `STAT_TEST_API`.

Do not select every non-`static` function. Explicit annotation prevents accidental growth of the test ABI.

### 2. Parse in production mode, not test-export mode

A useful detail: parse the source with `SQLITE_TEST` **undefined**, so:

```c
STAT_TEST_API
```

expands to:

```c
static
```

This preserves the source’s normal implementation semantics while the marker remains visible in the unexpanded source text.

For AST extraction, you can identify the function by examining the original source extent or tokens. Libclang source extents identify the source region corresponding to a cursor, and tokenization gives the lexical tokens in that range. ([Clang][1])

Alternatively, define a separate parser-only form:

```cmd
-DSTAT_TEST_API=__attribute__((annotate("stat_test_api")))
```

But that only works cleanly when the source lets the command-line definition override the normal macro definition. A dedicated marker macro is usually simpler.

### 3. Build a shared intermediate model

Do not emit text directly while walking cursors. First collect normalized records:

```python
from dataclasses import dataclass


@dataclass(frozen=True)
class Parameter:
    name: str
    c_type: str


@dataclass(frozen=True)
class Function:
    name: str
    result_type: str
    parameters: tuple[Parameter, ...]
    variadic: bool
    source_file: str
    source_line: int
```

For your examples:

```python
Function(
    name="utf8_length",
    result_type="sqlite3_int64",
    parameters=(
        Parameter(name="z", c_type="const char *"),
    ),
    variadic=False,
    source_file="alphabet.c",
    source_line=123,
)
```

Then write two independent emitters:

```python
emit_header(functions)
emit_ctypes_module(functions)
```

### 4. Extracting functions with libclang

A minimal extractor:

```python
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from clang.cindex import (
    Cursor,
    CursorKind,
    Index,
    TranslationUnit,
)


@dataclass(frozen=True)
class Parameter:
    name: str
    c_type: str


@dataclass(frozen=True)
class Function:
    name: str
    result_type: str
    parameters: tuple[Parameter, ...]
    variadic: bool
    source_file: Path
    source_line: int


def cursor_source_text(cursor: Cursor) -> str:
    start = cursor.extent.start
    end = cursor.extent.end

    if start.file is None or end.file is None:
        return ""

    if start.file.name != end.file.name:
        return ""

    path = Path(start.file.name)
    data = path.read_bytes()

    return data[start.offset : end.offset].decode(
        "utf-8",
        errors="replace",
    )


def is_test_api_function(cursor: Cursor) -> bool:
    if cursor.kind != CursorKind.FUNCTION_DECL:
        return False

    if not cursor.is_definition():
        return False

    if cursor.location.file is None:
        return False

    source = cursor_source_text(cursor)
    signature = source.split("{", 1)[0]

    return "STAT_TEST_API" in signature


def extract_function(cursor: Cursor) -> Function:
    parameters = tuple(
        Parameter(
            name=argument.spelling,
            c_type=argument.type.spelling,
        )
        for argument in cursor.get_arguments()
    )

    return Function(
        name=cursor.spelling,
        result_type=cursor.result_type.spelling,
        parameters=parameters,
        variadic=cursor.type.is_function_variadic(),
        source_file=Path(cursor.location.file.name),
        source_line=cursor.location.line,
    )


def walk(cursor: Cursor):
    yield cursor

    for child in cursor.get_children():
        yield from walk(child)


def parse_functions(
    source: Path,
    clang_args: list[str],
) -> list[Function]:
    index = Index.create()

    translation_unit = index.parse(
        str(source),
        args=clang_args,
        options=(
            TranslationUnit.PARSE_DETAILED_PROCESSING_RECORD
        ),
    )

    errors = [
        diagnostic
        for diagnostic in translation_unit.diagnostics
        if diagnostic.severity >= diagnostic.Error
    ]

    if errors:
        rendered = "\n".join(str(item) for item in errors)
        raise RuntimeError(
            f"Clang failed to parse {source}:\n{rendered}"
        )

    source_resolved = source.resolve()

    functions: list[Function] = []

    for cursor in walk(translation_unit.cursor):
        if not is_test_api_function(cursor):
            continue

        if Path(cursor.location.file.name).resolve() != source_resolved:
            continue

        functions.append(extract_function(cursor))

    functions.sort(key=lambda item: (item.source_line, item.name))
    return functions
```

The same-file check is important. Otherwise, traversal may collect functions from included headers.

#### One correction to the source-text helper

Reading `extent.start.offset:end.offset` works when the source is ordinary UTF-8-compatible text and Clang’s offsets refer to the same byte stream. Since the offsets are byte offsets, use `read_bytes()` as above, not `read_text()` followed by Python string slicing.

### 5. Generating the C header

A basic header emitter:

```python
def format_c_parameter(parameter: Parameter) -> str:
    name = parameter.name or "arg"

    c_type = parameter.c_type.strip()

    if c_type.endswith("*"):
        return f"{c_type}{name}"

    return f"{c_type} {name}"


def format_c_function(function: Function) -> str:
    if function.parameters:
        parameters = ",\n".join(
            f"    {format_c_parameter(parameter)}"
            for parameter in function.parameters
        )
    else:
        parameters = "    void"

    if function.variadic:
        if function.parameters:
            parameters += ",\n    ..."
        else:
            parameters = "    ..."

    return (
        f"STAT_TEST_DECL {function.result_type}\n"
        f"{function.name}(\n"
        f"{parameters}\n"
        f");"
    )


def emit_header(
    functions: list[Function],
    output: Path,
) -> None:
    declarations = "\n\n".join(
        format_c_function(function)
        for function in functions
    )

    text = f"""\
#ifndef STAT_TEST_API_GENERATED_H
#define STAT_TEST_API_GENERATED_H

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
# define STAT_TEST_DECL __declspec(dllimport)
#else
# define STAT_TEST_DECL
#endif

#ifdef __cplusplus
extern "C" {{
#endif

{declarations}

#ifdef __cplusplus
}}
#endif

#endif
"""

    output.write_text(text, encoding="utf-8", newline="\n")
```

Generated result:

```c
#ifndef STAT_TEST_API_GENERATED_H
#define STAT_TEST_API_GENERATED_H

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
# define STAT_TEST_DECL __declspec(dllimport)
#else
# define STAT_TEST_DECL
#endif

#ifdef __cplusplus
extern "C" {
#endif

STAT_TEST_DECL sqlite3_int64
utf8_length(
    const char *z
);

STAT_TEST_DECL int
utf8_decode_one(
    const unsigned char *z,
    size_t n,
    uint32_t *codepoint,
    size_t *consumed
);

#ifdef __cplusplus
}
#endif

#endif
```

#### Important limitation

`argument.type.spelling` is adequate for ordinary parameters such as:

```c
const unsigned char *
size_t
uint32_t *
```

It is not sufficient for every legal C declarator.

For example:

```c
int (*callback)(const void *, size_t)
```

cannot be reconstructed correctly by blindly writing:

```text
<type spelling> <name>
```

The parameter name belongs inside the function-pointer declarator.

For complex declarators, use one of these strategies:

1. Restrict the test ABI to simple scalar, pointer, array, and named-structure types.
2. Preserve the original source tokens for the complete function signature.
3. Implement a recursive C declarator renderer based on `TypeKind`.
4. Introduce typedefs for callbacks:

```c
typedef int (*stat_callback)(const void *, size_t);

STAT_TEST_API int
run_callback(stat_callback callback);
```

For a test ABI, **named callback typedefs are the best solution**.

### 6. Better header generation: preserve the original signature

For maximum fidelity, extract the original signature text before the opening function body:

```python
def extract_signature_source(cursor: Cursor) -> str:
    source = cursor_source_text(cursor)

    brace_index = source.find("{")
    if brace_index < 0:
        raise RuntimeError(
            f"Could not locate body for {cursor.spelling}"
        )

    signature = source[:brace_index].rstrip()

    signature = signature.replace(
        "STAT_TEST_API",
        "STAT_TEST_DECL",
        1,
    )

    return signature + ";"
```

This preserves:

* multiline formatting;
* function-pointer parameters;
* array declarators;
* macro-based types;
* pointer qualifiers;
* calling-convention macros.

Then:

```python
def emit_header_from_source(
    cursors: list[Cursor],
    output: Path,
) -> None:
    declarations = "\n\n".join(
        extract_signature_source(cursor)
        for cursor in cursors
    )

    # Add header guard and prerequisite includes.
```

This is usually the strongest approach for generating the `.h`.

Use the AST to:

* decide which functions qualify;
* validate names and linkage;
* sort and deduplicate;
* inspect dependencies.

Use the original source range to:

* reproduce the declaration.

### 7. Generating a `ctypes` module

Yes, the same `Function` records can generate:

```python
import ctypes


def bind(dll: ctypes.CDLL) -> None:
    dll.utf8_length.argtypes = [
        ctypes.c_char_p,
    ]
    dll.utf8_length.restype = ctypes.c_int64

    dll.utf8_decode_one.argtypes = [
        ctypes.POINTER(ctypes.c_ubyte),
        ctypes.c_size_t,
        ctypes.POINTER(ctypes.c_uint32),
        ctypes.POINTER(ctypes.c_size_t),
    ]
    dll.utf8_decode_one.restype = ctypes.c_int
```

The main work is a **C type → ctypes expression mapper**.

### 8. Do not map only from `type.spelling`

String mapping is tempting:

```python
{
    "int": "ctypes.c_int",
    "size_t": "ctypes.c_size_t",
    "sqlite3_int64": "ctypes.c_int64",
}
```

It works for a narrow API, but AST type kinds are more robust.

Use:

* `type.kind`;
* `type.get_canonical()`;
* `type.get_pointee()`;
* typedef spelling where semantically useful;
* declaration cursors for records and enums.

Libclang provides cursor and type inspection, including complete type information, pointee types, and qualifiers; canonical types can be used to strip typedefs when reasoning about the underlying representation. ([Clang][1])

### 9. A practical type mapper

```python
from clang.cindex import Type, TypeKind


DIRECT_CTYPES = {
    TypeKind.BOOL: "ctypes.c_bool",
    TypeKind.CHAR_S: "ctypes.c_char",
    TypeKind.SCHAR: "ctypes.c_int8",
    TypeKind.UCHAR: "ctypes.c_uint8",
    TypeKind.SHORT: "ctypes.c_short",
    TypeKind.USHORT: "ctypes.c_ushort",
    TypeKind.INT: "ctypes.c_int",
    TypeKind.UINT: "ctypes.c_uint",
    TypeKind.LONG: "ctypes.c_long",
    TypeKind.ULONG: "ctypes.c_ulong",
    TypeKind.LONGLONG: "ctypes.c_longlong",
    TypeKind.ULONGLONG: "ctypes.c_ulonglong",
    TypeKind.FLOAT: "ctypes.c_float",
    TypeKind.DOUBLE: "ctypes.c_double",
}


NAMED_TYPE_OVERRIDES = {
    "size_t": "ctypes.c_size_t",
    "ptrdiff_t": "ctypes.c_ssize_t",
    "int8_t": "ctypes.c_int8",
    "uint8_t": "ctypes.c_uint8",
    "int16_t": "ctypes.c_int16",
    "uint16_t": "ctypes.c_uint16",
    "int32_t": "ctypes.c_int32",
    "uint32_t": "ctypes.c_uint32",
    "int64_t": "ctypes.c_int64",
    "uint64_t": "ctypes.c_uint64",
    "sqlite3_int64": "ctypes.c_int64",
    "sqlite3_uint64": "ctypes.c_uint64",
}


class UnsupportedCTypeError(RuntimeError):
    pass


def ctypes_expression(
    c_type: Type,
    *,
    for_result: bool = False,
) -> str:
    spelling = " ".join(c_type.spelling.split())

    if spelling in NAMED_TYPE_OVERRIDES:
        return NAMED_TYPE_OVERRIDES[spelling]

    if c_type.kind == TypeKind.VOID:
        if for_result:
            return "None"

        raise UnsupportedCTypeError(
            "void is not a valid argument type"
        )

    if c_type.kind in DIRECT_CTYPES:
        return DIRECT_CTYPES[c_type.kind]

    if c_type.kind == TypeKind.TYPEDEF:
        override = NAMED_TYPE_OVERRIDES.get(spelling)
        if override is not None:
            return override

        return ctypes_expression(
            c_type.get_canonical(),
            for_result=for_result,
        )

    if c_type.kind == TypeKind.ENUM:
        # C enum ABI is normally int for this controlled interface.
        return "ctypes.c_int"

    if c_type.kind == TypeKind.POINTER:
        pointee = c_type.get_pointee()
        pointee_spelling = " ".join(pointee.spelling.split())

        if pointee.kind == TypeKind.VOID:
            return "ctypes.c_void_p"

        if (
            pointee.kind == TypeKind.CHAR_S
            and pointee.is_const_qualified()
        ):
            return "ctypes.c_char_p"

        inner = ctypes_expression(pointee)
        return f"ctypes.POINTER({inner})"

    raise UnsupportedCTypeError(
        f"Unsupported C type: "
        f"{c_type.spelling!r} ({c_type.kind})"
    )
```

#### Deliberately strict behavior

Do not silently guess unsupported types.

The generator should fail on:

* structures not yet emitted;
* unions;
* arrays;
* callbacks;
* `long double`;
* vectors;
* complex numbers;
* incomplete types;
* variadic functions.

A failed generation step is safer than an ABI-incorrect Python module.

### 10. Preserve actual Clang `Type` objects internally

The earlier `Function` model stores only strings. For `ctypes`, keep the original type information:

```python
@dataclass(frozen=True)
class ParsedParameter:
    name: str
    c_type: object  # clang.cindex.Type


@dataclass(frozen=True)
class ParsedFunction:
    name: str
    result_type: object
    parameters: tuple[ParsedParameter, ...]
    variadic: bool
    signature_source: str
    source_line: int
```

Or normalize the type into your own language-neutral model:

```python
@dataclass(frozen=True)
class CType:
    kind: str
    spelling: str
    const: bool = False
    pointee: "CType | None" = None
```

The second design is better for testing the generator itself and avoids retaining libclang objects after the translation unit goes out of scope.

### 11. Emit the binding module

```python
def emit_ctypes_module(
    functions,
    output: Path,
) -> None:
    lines = [
        '"""Generated ctypes declarations. Do not edit."""',
        "",
        "from __future__ import annotations",
        "",
        "import ctypes",
        "",
        "",
        "def bind(dll: ctypes.CDLL) -> ctypes.CDLL:",
    ]

    if not functions:
        lines.append("    return dll")
    else:
        for function in functions:
            if function.variadic:
                raise RuntimeError(
                    f"Variadic function is unsupported: "
                    f"{function.name}"
                )

            argument_types = [
                ctypes_expression(parameter.c_type)
                for parameter in function.parameters
            ]

            result_type = ctypes_expression(
                function.result_type,
                for_result=True,
            )

            lines.append(
                f"    dll.{function.name}.argtypes = ["
            )

            for argument_type in argument_types:
                lines.append(f"        {argument_type},")

            lines.append("    ]")
            lines.append(
                f"    dll.{function.name}.restype = "
                f"{result_type}"
            )
            lines.append("")

        lines.append("    return dll")

    lines.append("")

    output.write_text(
        "\n".join(lines),
        encoding="utf-8",
        newline="\n",
    )
```

Generated module:

```python
"""Generated ctypes declarations. Do not edit."""

from __future__ import annotations

import ctypes


def bind(dll: ctypes.CDLL) -> ctypes.CDLL:
    dll.utf8_length.argtypes = [
        ctypes.c_char_p,
    ]
    dll.utf8_length.restype = ctypes.c_int64

    dll.utf8_decode_one.argtypes = [
        ctypes.POINTER(ctypes.c_uint8),
        ctypes.c_size_t,
        ctypes.POINTER(ctypes.c_uint32),
        ctypes.POINTER(ctypes.c_size_t),
    ]
    dll.utf8_decode_one.restype = ctypes.c_int

    return dll
```

Usage:

```python
import ctypes
from pathlib import Path

from pytestenv._native_generated import bind


dll = bind(
    ctypes.CDLL(
        str(Path("build") / "sqlite3.dll")
    )
)
```

### 12. `const char *` requires a policy decision

The mapper above emits:

```python
ctypes.c_char_p
```

for:

```c
const char *
```

That is appropriate for NUL-terminated text.

It is not appropriate when the same type is used for:

* arbitrary binary data;
* buffers containing embedded NULs;
* memory that C modifies despite a bad declaration;
* an output buffer;
* a pointer paired with an explicit byte length.

For a binary buffer:

```c
const unsigned char *data,
size_t size
```

generate:

```python
ctypes.POINTER(ctypes.c_uint8)
```

For text:

```c
const char *text
```

generate:

```python
ctypes.c_char_p
```

The C type alone does not always encode enough semantic intent. A practical generator therefore needs:

* strict ABI mapping;
* optionally, small per-symbol overrides.

For example:

```python
TYPE_OVERRIDES = {
    ("decode_blob", "data"): (
        "ctypes.POINTER(ctypes.c_uint8)"
    ),
}
```

### 13. Structures and unions

For:

```c
typedef struct DecodeResult {
    uint32_t codepoint;
    size_t consumed;
} DecodeResult;
```

generate:

```python
class DecodeResult(ctypes.Structure):
    _fields_ = [
        ("codepoint", ctypes.c_uint32),
        ("consumed", ctypes.c_size_t),
    ]
```

Then map:

```c
DecodeResult *
```

to:

```python
ctypes.POINTER(DecodeResult)
```

The required extraction order is:

1. typedefs;
2. enum constants;
3. structures and unions;
4. callback typedefs;
5. variables;
6. functions.

You must also topologically order structure declarations when one structure contains another by value.

Pointers can use forward declarations:

```python
class Node(ctypes.Structure):
    pass


Node._fields_ = [
    ("next", ctypes.POINTER(Node)),
]
```

### 14. Exported variables

Libclang can also collect `CursorKind.VAR_DECL` cursors bearing your marker.

Generated Python helper:

```python
def bind_variables(dll: ctypes.CDLL):
    return {
        "stat_test_counter": ctypes.c_int.in_dll(
            dll,
            "stat_test_counter",
        ),
    }
```

But accessor functions remain preferable:

```c
STAT_TEST_API int
stat_test_get_counter(void);

STAT_TEST_API void
stat_test_set_counter(int value);
```

They produce a more stable and controllable test ABI.

### 15. Recommended first implementation scope

Start with these supported C types:

* `void` return;
* `char`, signed and unsigned integer types;
* fixed-width integer typedefs;
* `size_t`;
* `float`;
* `double`;
* enums as `int`;
* pointers to supported scalar types;
* `const char *`;
* `void *`;
* named structures;
* pointers to named structures.

Reject initially:

* variadic functions;
* arrays as parameters;
* function pointers;
* anonymous structures;
* unions;
* bit-fields;
* `_Complex`;
* compiler vector types;
* structures returned by value;
* `long double`;
* C++ declarations.

That covers nearly every good test-facing C ABI.

### 16. Verify generated declarations against the DLL

Generation from source proves that declarations exist in the source. It does not prove the resulting DLL exported them.

Add a pytest session check:

```python
def test_all_generated_symbols_are_exported(native_dll):
    expected = [
        "utf8_length",
        "utf8_decode_one",
    ]

    missing = [
        name
        for name in expected
        if not hasattr(native_dll, name)
    ]

    assert not missing, (
        "Missing native test exports: "
        + ", ".join(missing)
    )
```

The generated module can expose:

```python
EXPORTED_FUNCTIONS = (
    "utf8_length",
    "utf8_decode_one",
)
```

Then:

```python
from pytestenv._native_generated import EXPORTED_FUNCTIONS
```

### 17. Recommended final architecture

```text
tools/
    generate_test_api.py

src/
    alphabet.c

pytestenv/
    src/
        pytestenv/
            _native_generated.py
            native.py
    tests/
        conftest.py
        test_native_exports.py

build/
    generated/
        alphabet_test_api.h
```

Generator invocation:

```cmd
python tools\generate_test_api.py ^
  --source src\alphabet.c ^
  --header build\generated\alphabet_test_api.h ^
  --ctypes pytestenv\src\pytestenv\_native_generated.py ^
  --clang-arg=-std=c11 ^
  --clang-arg=-Isqlite ^
  --clang-arg=-Isrc
```

The generated header is useful for:

* ABI inspection;
* optional external consumers;
* documentation;
* feeding other binding tools;
* checking declarations with a C compiler.

The generated Python module is what pytest actually needs.

The best implementation is therefore **not**:

```text
.c → .h → parse .h → ctypes
```

It is:

```text
.c → libclang AST
       ├── faithful .h from source signatures
       └── ctypes declarations from semantic types
```

This gives you one parser run, one selection policy, and two deterministic outputs.

[1]: https://clang.llvm.org/docs/LibClang.html "Libclang tutorial — Clang 24.0.0git documentation"

---
---

## 📗 `ctypes` Definitions Generator Specification

> [!NOTE] Prompt
> 
> I am actually less concerned about header generation, which in my mental model was a source for the current objective of `ctypes` definitions generation. So let's create a specification for a single module libclang-based `ctypes` definitions generator. The C header generation task is taken out of current scope. I want, however, include a literal copy of function declaration extracted from the source `.c` as a comment to the associated `ctypes` definition. Integrate all your suggestions into a specification for AI implementation, providing a comprehensive and rigorous definition of robust tool.  

