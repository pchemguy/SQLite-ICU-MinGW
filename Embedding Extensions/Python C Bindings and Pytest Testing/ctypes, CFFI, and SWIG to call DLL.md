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
