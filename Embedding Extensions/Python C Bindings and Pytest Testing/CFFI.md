---
url: https://chatgpt.com/c/6a6acd3d-a91c-83eb-b3fb-a0bd8cbcaf63
---

## 📗 CFFI Workflow

> [!NOTE] Prompt
> 
> Talk to me about CFFI. It does not actually parse sources, does it? You actually provide individual prototypes to cdef?

Correct. **CFFI is not a source-code or header-discovery system.** It does not inspect your `.c` files, find exported functions, or automatically construct a Python API.

You explicitly provide C declarations to `ffi.cdef()`:

```python
from cffi import FFI

ffi = FFI()

ffi.cdef("""
    int32_t ctd_add(int32_t a, int32_t b);
    void ctd_scale(double *values, size_t count, double factor);
    const char *ctd_name(void);
""")

lib = ffi.dlopen("ctd.dll")
```

`cdef()` does perform parsing, using a C parser internally, but it parses **the declaration text you supplied**, not the actual library source. It accepts a restricted, preprocessed-like subset of C declarations and generally cannot consume a normal header containing arbitrary `#include`, macros, compiler attributes, and conditional compilation. ([CFFI][1])

### You need not call `cdef()` once per prototype

You can provide one large declaration block:

```python
ffi.cdef("""
    typedef struct {
        int32_t x;
        int32_t y;
    } ctd_point;

    int32_t ctd_scalar_zero(void);
    int32_t ctd_scalar_one(int32_t value);

    void ctd_array_in(
        const int32_t *values,
        size_t count
    );

    int ctd_array_out(
        int32_t **values,
        size_t *count
    );
""")
```

You can also read declaration text from a prepared file:

```python
from pathlib import Path
from cffi import FFI

ffi = FFI()
ffi.cdef(Path("ctd.cdef.h").read_text(encoding="utf-8"))
```

But that file must still be written or generated as a **CFFI-compatible declaration file**. CFFI does not itself derive it from your implementation.

### `cdef()` versus `set_source()`

These serve different purposes.

#### `cdef()`: what Python may access

```python
ffibuilder.cdef("""
    int ctd_add(int a, int b);
""")
```

This tells CFFI:

* the symbol name;
* argument types;
* return type;
* referenced structures, typedefs, enums and globals.

It is effectively CFFI’s interface description.

#### `set_source()`: what the C compiler sees

In API mode:

```python
ffibuilder.set_source(
    "_ctd",
    """
    #include "ctd.h"
    """,
    libraries=["ctd"],
)
```

The text supplied to `set_source()` is ordinary C code and may contain real includes, macros and compiler-specific declarations. CFFI places it into a generated C extension and invokes the C compiler. ([CFFI][2])

A normal API-mode build therefore often contains the declaration twice conceptually:

```python
ffibuilder.cdef("""
    int ctd_add(int a, int b);
""")

ffibuilder.set_source(
    "_ctd",
    """
    #include "ctd.h"
    """,
)
```

The compiler sees `ctd.h`, but CFFI still needs the `cdef()` declaration to know which interface to expose.

### ABI mode does not compile against the header

```python
ffi = FFI()
ffi.cdef("""
    int ctd_add(int a, int b);
""")
lib = ffi.dlopen("ctd.dll")
```

Here CFFI trusts that the DLL really exports a function compatible with that declaration. It does not compare the declaration against the original header.

A wrong declaration may produce:

* corrupted arguments;
* corrupted returns;
* crashes;
* calling-convention failures;
* incorrect structure layouts.

This is broadly analogous to manually assigning `argtypes` and `restype` in `ctypes`, except that CFFI accepts C-like declarations and has a richer C type model.

### API mode can let the compiler verify more

In out-of-line API mode, CFFI generates C code that refers to the actual declarations included through `set_source()`. This lets the compiler catch many mismatches. CFFI also supports `...` placeholders for details that the compiler should determine:

```python
ffibuilder.cdef("""
    typedef struct {
        int32_t code;
        ...;
    } ctd_result;

    enum ctd_status {
        CTD_OK,
        CTD_ERROR,
        ...
    };
""")
```

The actual definitions are obtained through the real headers seen by the compiler. This is considerably safer than ABI mode, but CFFI still does not discover the declarations to expose. You select and describe those in `cdef()`. ([CFFI][1])

### CFFI is not a semantic wrapper generator

For your pointer-policy work, the crucial limitation is that CFFI only understands **C types**, not the higher-level contract.

Given:

```c
int ctd_fetch(int32_t **data, size_t *count);
```

CFFI does not know that:

* `data` is an output;
* `*data` points to an array;
* `*count` is its element count;
* the memory is owned by the callee;
* Python must copy the data;
* the pointer may be null;
* the return value is a status code;
* the array contains exactly `*count` elements.

You must implement that behavior yourself:

```python
data_p = ffi.new("int32_t **")
count_p = ffi.new("size_t *")

status = lib.ctd_fetch(data_p, count_p)
if status != 0:
    raise RuntimeError(f"ctd_fetch failed: {status}")

result = list(ffi.unpack(data_p[0], count_p[0]))
```

Likewise, for:

```c
int ctd_write(char *buffer, size_t capacity, size_t *written);
```

CFFI cannot infer that `capacity` describes `buffer`, that `written` is an output count, or whether the result is bytes or UTF-8 text.

### Practical conclusion

CFFI replaces much of the **low-level call machinery** that you would otherwise write with `ctypes`:

* C declaration parsing;
* C data allocation;
* pointer construction and dereferencing;
* structure and array access;
* conversions between C buffers and Python bytes;
* dynamic loading;
* optional compiled wrappers.

It does **not** replace:

* source/header extraction;
* preprocessing;
* API discovery;
* direction annotations;
* array-length relationships;
* ownership rules;
* nullability;
* string encoding policy;
* semantic Python wrapper generation.

So for your intended system, CFFI could be the execution backend, but you would still need your annotation schema and wrapper generator. The main difference from a `ctypes` backend is that you could emit a CFFI `cdef()` block instead of emitting `argtypes`, `restype`, and many explicit ctypes type constructions.

[1]: https://cffi.readthedocs.io/en/latest/cdef.html "Preparing Wrapper Modules — CFFI 2.2.0.dev0 documentation"
[2]: https://cffi.readthedocs.io/en/stable/overview.html "Overview — CFFI 2.1.0 documentation"

---
---

## 📗 ABI vs API

> [!NOTE] Prompt
> 
> Give me systematic and comprehensive overview of ABI vs API mode.

