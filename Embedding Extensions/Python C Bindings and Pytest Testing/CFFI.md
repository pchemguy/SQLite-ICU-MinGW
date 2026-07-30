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

## 📗 CFFI ABI mode versus API mode

> [!NOTE] Prompt
> 
> Give me systematic and comprehensive overview of ABI vs API mode.

The distinction is fundamentally **how Python reaches the C function**:

* **ABI mode:** CFFI loads an already-built shared library and calls its exported machine-code symbols dynamically.
* **API mode:** CFFI generates and compiles a Python extension containing C wrappers that call the target C API as ordinary compiled C code.

Both modes use `cdef()` to describe the interface exposed to Python. Neither mode automatically discovers the desired functions from your `.c` sources. The difference is what CFFI does with those declarations afterward. ([CFFI][1])

---

### 1. Minimal conceptual comparison

Given this C function:

```c
int ctd_add(int a, int b);
```

##### ABI mode

```python
from cffi import FFI

ffi = FFI()
ffi.cdef("""
    int ctd_add(int a, int b);
""")

lib = ffi.dlopen("ctd.dll")

result = lib.ctd_add(2, 3)
```

The path is approximately:

```text
Python
  ↓
CFFI/libffi dynamic call machinery
  ↓
look up ctd_add in ctd.dll
  ↓
call address using declared ABI
```

##### API mode

Build script:

```python
from cffi import FFI

ffibuilder = FFI()

ffibuilder.cdef("""
    int ctd_add(int a, int b);
""")

ffibuilder.set_source(
    "_ctd",
    """
    #include "ctd.h"
    """,
    libraries=["ctd"],
    include_dirs=["include"],
    library_dirs=["lib"],
)

if __name__ == "__main__":
    ffibuilder.compile(verbose=True)
```

Runtime:

```python
from _ctd import ffi, lib

result = lib.ctd_add(2, 3)
```

The path is approximately:

```text
Python
  ↓
generated compiled CPython/CFFI wrapper
  ↓
ordinary compiled C call to ctd_add()
  ↓
linker-resolved target library
```

API mode therefore produces a platform-specific extension such as `_ctd.pyd` on Windows or `_ctd.so` on Unix-like systems. ([CFFI][1])

---

### 2. What “ABI” and “API” mean here

#### ABI: Application Binary Interface

An ABI defines the machine-level contract between compiled components, including such details as:

* symbol naming;
* calling convention;
* argument placement;
* return-value placement;
* register usage;
* stack layout;
* structure layout;
* alignment and padding;
* integer and floating-point representation;
* enum representation;
* data-symbol access.

In ABI mode, your `cdef()` declaration must describe that binary contract accurately enough for CFFI to perform the call without consulting the original compiler.

For example:

```python
ffi.cdef("""
    long ctd_value(void);
""")
```

CFFI must decide the size and ABI behavior of `long` from the current Python/CFFI platform. If the loaded DLL was built for a different or incompatible ABI, the declaration can be wrong even though it appears syntactically reasonable.

ABI mode is therefore effectively saying:

> Trust this declaration as the binary truth and invoke the DLL accordingly.

#### API: Application Programming Interface

An API is the source-level C contract:

```c
#include "ctd.h"

int result = ctd_add(2, 3);
```

The compiler sees the real declaration and generates the correct machine-level call for the target environment.

API mode is effectively saying:

> Compile a C wrapper against the actual declarations, and let the compiler determine the ABI details.

This is why API mode is more robust when types, structures, macros, platform-dependent typedefs, or compiler conventions are involved. ([CFFI][1])

---

### 3. `cdef()` has different authority in each mode

This is one of the most important distinctions.

#### ABI mode: `cdef()` is the operative binary declaration

```python
ffi.cdef("""
    int ctd_read(long index, double *value);
""")

lib = ffi.dlopen("ctd.dll")
```

CFFI does not compare this declaration with `ctd.h`.

If the actual function is:

```c
int ctd_read(int64_t index, float *value);
```

the discrepancy may not be detected. Depending on the platform and exact mismatch, the result may be:

* incorrect values;
* overwritten memory;
* stack or register corruption;
* access violations;
* immediate process crashes;
* bugs that only appear on one architecture.

CFFI’s documentation explicitly warns that ABI mode can crash when functions or structures are misdeclared. ([CFFI][1])

#### API mode: `cdef()` describes the Python-facing interface, while the compiler sees the actual C declarations

```python
ffibuilder.cdef("""
    int ctd_read(int64_t index, double *value);
""")

ffibuilder.set_source(
    "_ctd",
    """
    #include "ctd.h"
    """,
)
```

The generated C source includes `ctd.h`. Consequently, the compiler participates in checking and adapting the calls.

However, this does **not** mean every possible `cdef()` mistake is guaranteed to produce a clean compiler error. The generated wrapper can include casts or conversions, and some compatible-but-semantically-wrong declarations may still compile.

API mode substantially improves verification, but it is not a formal proof that the `cdef()` and header describe identical semantics.

---

### 4. The two independent axes: ABI/API and inline/out-of-line

CFFI actually describes four combinations:

| Interface level | Preparation style | Current role                                      |
| --------------- | ----------------- | ------------------------------------------------- |
| ABI             | inline            | Simple direct use                                 |
| ABI             | out-of-line       | Pre-generated declarations, still dynamic loading |
| API             | out-of-line       | Preferred compiled API mode                       |
| API             | inline            | Deprecated `ffi.verify()` model                   |

The current normal choices are:

1. **Inline ABI**
2. **Out-of-line ABI**
3. **Out-of-line API**

Inline API through `ffi.verify()` is deprecated in favor of out-of-line API through `set_source()`. ([CFFI][1])

---

### 5. Inline ABI mode

This is the simplest form.

```python
from cffi import FFI

ffi = FFI()

ffi.cdef("""
    int ctd_add(int a, int b);
""")

lib = ffi.dlopen("ctd.dll")
```

#### Properties

* No project-specific C compilation step.
* C declarations are parsed when the Python module is imported or initialized.
* The target library must already exist.
* The library is opened explicitly with `ffi.dlopen()`.
* Calls use CFFI’s generic ABI call machinery.
* Large `cdef()` blocks add parsing and setup work at import time.

#### Appropriate uses

* exploratory access to a DLL;
* small test harnesses;
* prototypes;
* runtime-selected libraries;
* environments where no compiler is available;
* interfaces consisting mostly of simple scalar and pointer types;
* generated test code where declarations are already mechanically controlled.

#### Main weakness

All ABI correctness rests on the generated or handwritten declaration.

---

### 6. Out-of-line ABI mode

Build script:

```python
from cffi import FFI

ffibuilder = FFI()

ffibuilder.cdef("""
    int ctd_add(int a, int b);
""")

ffibuilder.set_source("_ctd_abi", None)

if __name__ == "__main__":
    ffibuilder.compile()
```

This produces a generated Python module, not a compiled C wrapper:

```python
from _ctd_abi import ffi

lib = ffi.dlopen("ctd.dll")
```

The decisive detail is:

```python
ffibuilder.set_source("_ctd_abi", None)
```

`None` means that no API-level C source is generated and compiled.

#### What it improves

* avoids reparsing a large declaration block during ordinary imports;
* separates binding generation from runtime use;
* makes packaging cleaner;
* permits expensive declaration preparation during the build/generation stage;
* still requires no target C compiler for the generated interface module itself.

#### What it does not improve

It remains ABI mode:

* `ffi.dlopen()` is still used;
* function calls still use generic dynamic-call machinery;
* declarations are still not compiler-verified against the real header;
* exact structure layouts still matter;
* ABI mistakes can still crash the process.

CFFI describes out-of-line ABI mode primarily as an organizational and import-time optimization, not as an ABI-safety improvement. ([CFFI][1])

---

### 7. Out-of-line API mode

This is CFFI’s preferred compiled mode.

```python
from cffi import FFI

ffibuilder = FFI()

ffibuilder.cdef("""
    int ctd_add(int a, int b);
""")

ffibuilder.set_source(
    "_ctd",
    """
    #include "ctd.h"
    """,
    include_dirs=["include"],
    libraries=["ctd"],
    library_dirs=["lib"],
)

if __name__ == "__main__":
    ffibuilder.compile(verbose=True)
```

The result is a native Python extension:

```text
_ctd.pyd       Windows
_ctd.so        Linux and similar systems
```

Runtime use:

```python
from _ctd import ffi, lib

result = lib.ctd_add(2, 3)
```

There is normally no Python-level `ffi.dlopen()` call because the generated extension was already compiled and linked against the relevant C interface. ([CFFI][1])

---

### 8. What `set_source()` actually contains

`cdef()` and `set_source()` are deliberately different languages.

#### `cdef()`

Contains CFFI declarations:

```python
ffibuilder.cdef("""
    typedef struct ctd_context ctd_context;

    int ctd_open(ctd_context **out);
    void ctd_close(ctd_context *ctx);
""")
```

It generally contains:

* typedef declarations;
* structure declarations;
* enum declarations;
* function prototypes;
* global-variable declarations;
* constants in forms CFFI supports.

It does not accept arbitrary normal header machinery such as `#include` and `#ifdef`. ([CFFI][1])

#### `set_source()`

Contains actual C source passed to the C compiler:

```python
ffibuilder.set_source(
    "_ctd",
    """
    #include <stdint.h>
    #include "ctd.h"

    static int ctd_wrapper(void){
        return ctd_original();
    }
    """,
)
```

It may contain:

* `#include`;
* macros;
* conditional compilation;
* compiler-specific declarations;
* helper wrappers;
* adapter functions;
* actual C implementation code.

This means API mode can expose either:

1. existing C functions from an external library;
2. C functions compiled directly into the Python extension;
3. custom adapter functions written specifically for Python.

---

### 9. Linking behavior

#### ABI mode

You identify the shared library at runtime:

```python
lib = ffi.dlopen(r"C:\project\build\ctd.dll")
```

The returned `lib` object represents that library namespace. Functions and globals declared in `cdef()` become available as attributes when matching symbols exist.

This is explicit and dynamic:

```python
core = ffi.dlopen("core.dll")
plugin = ffi.dlopen("plugin.dll")
```

A single `ffi` object can describe declarations used with several loaded libraries. ([CFFI][1])

#### API mode

The C compiler and linker resolve calls according to the extension build configuration:

```python
ffibuilder.set_source(
    "_ctd",
    '#include "ctd.h"',
    libraries=["ctd"],
    library_dirs=["build"],
)
```

The generated extension may:

* statically include the target implementation;
* statically link a library;
* dynamically depend on a DLL or shared library;
* contain wrapper code that calls symbols resolved by the native linker.

At runtime, importing `_ctd` causes the operating system’s native loader to resolve its dependencies.

Thus, API mode does not necessarily eliminate a DLL dependency. It eliminates **Python-controlled `dlopen()` as the ordinary binding mechanism**.

---

### 10. Structure handling

Structures expose one of the strongest practical differences.

Suppose the real header contains:

```c
typedef struct {
    int code;
    size_t count;
    void *data;
} ctd_result;
```

#### ABI mode

You might declare:

```python
ffi.cdef("""
    typedef struct {
        int code;
        size_t count;
        void *data;
    } ctd_result;
""")
```

CFFI must calculate the complete layout:

* offset of `code`;
* padding before `count`;
* offset of `count`;
* offset of `data`;
* total structure size;
* structure alignment.

Your declaration must match the DLL’s compiled layout.

Potential sources of mismatch include:

* 32-bit versus 64-bit builds;
* packing pragmas;
* compiler options;
* conditional fields;
* platform-dependent typedefs;
* different compiler ABIs;
* anonymous members;
* bit-fields;
* compiler extensions.

#### API mode

You can often write:

```python
ffibuilder.cdef("""
    typedef struct {
        int code;
        size_t count;
        ...;
    } ctd_result;
""")
```

and include the actual header:

```python
ffibuilder.set_source(
    "_ctd",
    """
    #include "ctd.h"
    """,
)
```

The literal `...` tells CFFI that the C compiler should provide missing layout information. CFFI specifically supports this style in API mode for structures and other declarations whose exact platform details should be determined by compilation. ([CFFI][1])

This is a major reason API mode is preferable for nontrivial public C APIs.

---

### 11. Opaque structures

Opaque handles work well in either mode:

```c
typedef struct ctd_context ctd_context;

ctd_context *ctd_create(void);
void ctd_destroy(ctd_context *ctx);
```

CFFI declaration:

```python
ffi.cdef("""
    typedef struct ctd_context ctd_context;

    ctd_context *ctd_create(void);
    void ctd_destroy(ctd_context *ctx);
""")
```

Python never needs the structure’s layout. It only holds and returns a pointer.

For APIs deliberately designed around opaque handles, the safety difference between ABI and API mode becomes smaller because CFFI does not need to reproduce internal structure layout.

That does not remove risks from function-signature, calling-convention, or typedef mismatches, but it removes a major category of ABI fragility.

---

### 12. Platform-dependent typedefs

Consider:

```c
typedef unsigned long ctd_size;
```

The width of `unsigned long` differs across common ABIs. In particular, Windows 64-bit and many Unix-like 64-bit systems do not use the same data model.

#### ABI mode

The Python runtime platform determines how CFFI interprets:

```python
ffi.cdef("""
    typedef unsigned long ctd_size;
""")
```

That is safe only when the Python process, CFFI, and loaded DLL all agree on the ABI.

#### API mode

The included real header lets the compiler apply the target platform’s actual typedef.

API mode is therefore much better suited to interfaces using:

* `long`;
* `size_t`;
* `ptrdiff_t`;
* compiler-defined integer aliases;
* platform handles;
* conditional typedefs;
* native structure definitions.

For tightly controlled C99 interfaces using `int32_t`, `uint64_t`, opaque pointers, and explicit calling conventions, ABI mode can be made much more predictable.

---

### 13. Macros and constants

Suppose the header contains:

```c
#define CTD_DEFAULT_CAPACITY 256
#define CTD_VERSION_MAJOR 3
```

These are preprocessor macros, not exported DLL symbols.

#### ABI mode

`ffi.dlopen()` cannot retrieve ordinary macros from a DLL because no symbol exists for them.

You must:

* duplicate the value in `cdef()` where supported;
* generate the value into Python;
* expose it through a real C function or exported variable;
* otherwise reproduce it manually.

#### API mode

Because a C compiler processes the actual header, CFFI can obtain more compile-time information and generate wrapper access to suitable constants. API mode is much better aligned with APIs that rely heavily on header-defined constants.

Neither mode turns arbitrary function-like macros into callable functions automatically. A wrapper may be needed:

```c
static int ctd_is_valid_wrapper(int x){
    return CTD_IS_VALID(x);
}
```

and then:

```python
ffibuilder.cdef("""
    int ctd_is_valid_wrapper(int x);
""")
```

---

### 14. Inline functions

A header may define:

```c
static inline int ctd_double(int value){
    return value * 2;
}
```

There is normally no exported symbol named `ctd_double` in the DLL.

#### ABI mode

This fails conceptually:

```python
ffi.cdef("""
    int ctd_double(int value);
""")

lib = ffi.dlopen("ctd.dll")
```

because `ffi.dlopen()` needs a real dynamically visible symbol.

#### API mode

The generated C wrapper includes the header and can call the inline function:

```python
ffibuilder.set_source(
    "_ctd",
    """
    #include "ctd.h"
    """
)
```

The compiler sees the inline implementation and can compile the call into the extension.

This also applies to many macro-based APIs that can be wrapped through actual C source.

---

### 15. Static functions and private implementation functions

Given:

```c
static int ctd_internal(int value){
    return value + 1;
}
```

#### ABI mode

It cannot call the function from an external DLL because a `static` function has internal linkage and is not exported as a dynamic symbol.

#### API mode

API mode can call it only when the generated wrapper is compiled in a context where that internal function is visible.

For example, this might work if source composition deliberately places the wrapper in the same translation unit:

```c
#include "ctd.c"

static int ctd_internal_wrapper(int value){
    return ctd_internal(value);
}
```

But merely linking a separately compiled `ctd.obj` does not expose its `static` functions.

In your test-build design, where selected internal functions become externally visible under `SQLITE_TEST`, either mode can call them once they are exported. API mode does not magically bypass C linkage.

---

### 16. Calling conventions

On Windows, calling convention can be ABI-critical:

```c
int __cdecl ctd_a(int x);
int __stdcall ctd_b(int x);
```

A mismatch can affect:

* symbol decoration;
* argument passing;
* stack cleanup;
* function-pointer compatibility.

#### ABI mode

The `cdef()` must correctly express the calling convention in a form CFFI supports.

Because the call is constructed dynamically, a mistake directly corrupts the binary call contract.

#### API mode

The compiler sees the actual header declarations and generates the call according to the compiler’s rules.

API mode is generally safer when calling conventions are hidden behind macros such as:

```c
#define CTD_API __declspec(dllexport)
#define CTD_CALL __stdcall
```

The `cdef()` still needs a reasonable interface representation, but the actual generated C call is compiled against the header.

---

### 17. Export requirements

#### ABI mode

The target must expose a runtime-loadable symbol.

On Windows:

```c
__declspec(dllexport)
int ctd_add(int a, int b);
```

or the equivalent `.def`-file export is necessary.

CFFI then looks it up through the loaded DLL.

#### API mode with a separate DLL

The extension still needs to link against the function. On Windows this normally means:

* the function is exported by the DLL;
* an import library is available, or another supported linking mechanism is used;
* the runtime DLL can be found when the extension is imported.

#### API mode with compiled-in sources

No DLL export is required if the C implementation is compiled directly into the generated extension:

```python
ffibuilder.set_source(
    "_ctd",
    '#include "ctd.h"',
    sources=["ctd.c"],
)
```

The C symbol only needs linkage suitable for the generated wrapper within that native module.

This can simplify distribution but changes the artifact model: Python is then using its own compiled copy of the C code, not necessarily the independently built DLL you wanted to test.

---

### 18. Runtime library selection

#### ABI mode advantage

The DLL can be selected dynamically:

```python
lib = ffi.dlopen(path_from_test_configuration)
```

This is valuable for testing:

```text
build/debug/ctd.dll
build/release/ctd.dll
build/asan/ctd.dll
build/current/ctd.dll
```

The same Python binding definition can load different binary builds.

#### API mode limitation

The native extension is normally built against a particular library identity and search configuration.

You can still replace the underlying DLL with another ABI-compatible DLL of the same name, but runtime selection is less explicit and may depend on:

* DLL search paths;
* loader behavior;
* import-library linkage;
* `PATH`;
* side-by-side placement;
* platform loader rules.

For a pytest system whose explicit purpose is to load and test arbitrary freshly built DLLs, ABI mode has a strong operational advantage.

---

### 19. Build requirements

#### ABI mode

At binding runtime or generation time, you need:

* Python;
* CFFI;
* a compatible prebuilt DLL/shared library.

You do not need to compile a project-specific Python extension.

CFFI itself may include native components as part of its installation, but your binding does not require a dedicated C compilation step.

#### API mode

You need a build environment capable of compiling a Python extension:

* C compiler;
* Python development headers and compatible build tooling;
* target headers;
* target libraries or sources;
* correct architecture;
* correct runtime and linker settings.

On Windows, this generally means using a compiler toolchain compatible with the Python interpreter and producing a `.pyd` for the appropriate Python version and architecture.

The compiler is needed when producing the extension. The resulting precompiled extension can then be distributed like another native Python extension. ([CFFI][1])

---

### 20. Distribution consequences

#### ABI mode distribution

Typical package contents:

```text
package/
    __init__.py
    binding.py
    ctd.dll
```

or with out-of-line ABI:

```text
package/
    __init__.py
    _ctd_abi.py
    ctd.dll
```

Advantages:

* Python binding code may be portable across several Python versions;
* replacing the DLL can be easy;
* no project-specific `.pyd` needs to be built;
* pure-Python binding-generation artifacts can be simpler.

But the DLL must still match:

* operating system;
* architecture;
* ABI;
* calling conventions;
* C runtime assumptions where applicable.

#### API mode distribution

Typical package contents:

```text
package/
    __init__.py
    _ctd.cp313-win_amd64.pyd
    ctd.dll
```

or the C implementation may be incorporated into `_ctd.pyd`.

The extension is usually specific to:

* operating system;
* architecture;
* Python implementation;
* often Python ABI/version;
* compiler/runtime environment.

This generally means producing wheels for each supported platform and Python combination.

---

### 21. Performance

CFFI states that API-mode calls are faster than ABI-mode calls. ABI mode uses generic libffi-style dynamic invocation, whereas API mode uses generated compiled wrappers that directly invoke the target C function. ([CFFI][1])

The practical importance depends on call granularity.

#### ABI overhead matters more when

* functions are tiny;
* calls occur millions of times;
* each call performs only a few arithmetic operations;
* scalar values cross the boundary repeatedly.

Example:

```c
double ctd_add(double a, double b);
```

called once per element is a poor boundary design in either mode, but ABI overhead will be more visible.

#### ABI overhead matters less when

* each C call processes a large array;
* each call performs substantial parsing or computation;
* file or database I/O dominates;
* Python-to-C crossing frequency is low.

Example:

```c
int ctd_transform(
    const float *input,
    size_t count,
    float *output
);
```

For large `count`, the actual C work may dominate the call overhead.

API mode does not eliminate Python/C conversion costs, allocations, copying, wrapper logic, or user-defined semantic adaptation.

---

### 22. Import-time behavior

#### Inline ABI

The process commonly includes:

1. instantiate `FFI`;
2. parse `cdef()` declarations;
3. call `ffi.dlopen()`;
4. resolve symbols as needed.

Large declaration blocks can make imports slower.

#### Out-of-line ABI

The declaration representation is prepared in advance, reducing ordinary import-time parsing work. The library is still loaded dynamically afterward. ([CFFI][1])

#### Out-of-line API

The generated native module is imported directly:

```python
from _ctd import ffi, lib
```

The operating-system loader resolves native dependencies, and no large runtime `cdef()` parse is required.

---

### 23. Error detection timing

#### ABI mode

Many problems appear only when the library is loaded or a function is called.

##### At `ffi.dlopen()`

You may detect:

* DLL not found;
* dependency not found;
* invalid library architecture;
* loader failures.

##### At attribute access

You may detect:

* symbol not found;
* symbol not exported;
* decorated-name mismatch.

##### At call time

You may encounter:

* wrong results;
* crashes;
* corrupted memory;
* invalid pointer behavior;
* calling-convention failures.

#### API mode

Many problems move to build time:

* missing header;
* unknown type;
* incompatible declaration;
* missing library;
* unresolved external symbol;
* invalid compiler option;
* unavailable inline or macro definition.

Some loader problems remain runtime problems:

* dependent DLL missing;
* incompatible replacement DLL;
* loader search-path issue;
* architecture mismatch.

Moving failures from runtime to compilation is one of API mode’s major engineering advantages.

---

### 24. Variables and data symbols

Suppose the DLL exports:

```c
extern int ctd_global_state;
```

#### ABI mode

You can declare and access it:

```python
ffi.cdef("""
    extern int ctd_global_state;
""")

lib = ffi.dlopen("ctd.dll")
print(lib.ctd_global_state)
```

This requires an actual exported data symbol with the expected ABI.

#### API mode

The generated wrapper refers to the variable through compiled C code. The compiler sees the declaration, and the linker resolves it.

API mode is safer for type correctness, but exported mutable global variables remain awkward API design because they introduce:

* synchronization concerns;
* initialization-order concerns;
* direct state mutation;
* versioning fragility.

Accessor functions are usually easier to stabilize:

```c
int ctd_get_global_state(void);
void ctd_set_global_state(int value);
```

---

### 25. Variadic functions

Example:

```c
int printf(const char *format, ...);
```

ABI mode can call variadic functions, but variadic arguments require explicit CFFI cdata objects of the correct promoted C types.

For example, passing a plain Python integer is not always sufficient for a variadic position; you may need:

```python
value = ffi.cast("int", 42)
lib.some_variadic(b"%d", value)
```

API mode can compile a direct call, but C variadic semantics still apply:

* default argument promotions;
* no type information for variadic positions;
* exact caller responsibility.

For a controlled test API, it is generally better to avoid exposing variadic functions and add a fixed-signature wrapper.

---

### 26. Function pointers and callbacks

Both modes can represent function pointers:

```python
ffi.cdef("""
    typedef int (*ctd_callback)(int value, void *context);

    int ctd_iterate(
        ctd_callback callback,
        void *context
    );
""")
```

However, the preferred callback facilities differ.

#### ABI-style callbacks

You can create callback objects dynamically with facilities such as `ffi.callback()`.

This is flexible but introduces:

* callback object lifetime management;
* Python exception handling across C boundaries;
* thread-entry concerns;
* performance overhead;
* platform-specific behavior.

#### API-mode extern-Python callbacks

Out-of-line API mode supports statically declared Python callbacks through `extern "Python"` and `ffi.def_extern()`. CFFI documents this as the newer, generally faster and more portable callback mechanism. ([CFFI][2])

For simple one-way calls from Python into C, this distinction is irrelevant. It matters when C retains and later invokes Python callbacks.

---

### 27. Threading and the GIL

ABI versus API mode does not by itself define the semantic thread-safety of the target library.

Questions remain:

* Is the C function thread-safe?
* May it call Python?
* Does it retain pointers into Python-managed memory?
* Does it use thread-local error state?
* Does it invoke callbacks from foreign threads?
* Can operations execute without holding the Python GIL?

CFFI-generated calls normally manage the Python/C transition according to CFFI’s runtime model, but API mode is more adaptable when custom C wrapper code is needed for specialized synchronization, callback routing, or library locking.

The binding mode cannot make a non-thread-safe C API thread-safe automatically.

---

### 28. Memory ownership is unchanged

Neither mode infers ownership.

Given:

```c
char *ctd_get_name(void);
```

neither mode knows whether the result is:

* static storage;
* newly allocated memory;
* caller-owned memory;
* valid until the next call;
* nullable;
* UTF-8;
* arbitrary bytes;
* required to be freed through `free()`;
* required to be freed through `ctd_free()`.

The wrapper still needs policy:

```python
ptr = lib.ctd_get_name()

if ptr == ffi.NULL:
    return None

result = ffi.string(ptr).decode("utf-8")
lib.ctd_free(ptr)
return result
```

ABI/API mode controls invocation mechanics and type integration. It does not replace the semantic annotation layer you are designing.

---

### 29. Array semantics are unchanged

Given:

```c
int ctd_values(const int32_t **data, size_t *count);
```

CFFI sees:

* pointer to pointer to `int32_t`;
* pointer to `size_t`;
* integer return value.

It does not know:

* `data` is output;
* `count` is output;
* `count` sizes `*data`;
* memory belongs to the callee;
* data must be copied before another call;
* null is allowed only when count is zero;
* return value is a status code.

Your Python wrapper still needs something like:

```python
data_out = ffi.new("const int32_t **")
count_out = ffi.new("size_t *")

status = lib.ctd_values(data_out, count_out)
if status != 0:
    raise RuntimeError(status)

if data_out[0] == ffi.NULL:
    if count_out[0] != 0:
        raise RuntimeError("invalid native result")
    return []

return list(ffi.unpack(data_out[0], count_out[0]))
```

The same wrapper logic applies in both ABI and API mode.

---

### 30. String semantics are unchanged

For:

```c
const char *ctd_name(void);
```

both modes know only that the function returns a pointer to `const char`.

They do not know whether it is:

* null-terminated;
* length-delimited elsewhere;
* UTF-8;
* Latin-1;
* filesystem encoding;
* arbitrary bytes;
* nullable;
* valid indefinitely;
* valid only temporarily.

Thus:

```python
raw = ffi.string(ptr)
text = raw.decode("utf-8")
```

is wrapper policy, not something API mode derives from the C compiler.

The compiler can verify the pointer type. It cannot infer the application-level encoding or lifetime contract.

---

### 31. What API mode can infer and what it cannot

#### API mode can use the compiler to determine

* exact structure layout;
* type sizes;
* alignments;
* enum values;
* platform typedefs;
* selected macro constants;
* correct source-level invocation;
* inline function definitions;
* compiler calling conventions;
* conditional header definitions;
* declarations selected by preprocessor macros.

#### API mode cannot infer

* input/output direction;
* ownership;
* allocation policy;
* array-length relationships;
* buffer capacity relationships;
* valid length versus capacity;
* nullability contract;
* text encoding;
* whether `char *` means bytes or text;
* whether a return integer is data, status, count, or boolean;
* error handling policy;
* whether output must be copied;
* mutation effects;
* aliasing restrictions;
* required call ordering.

This is the key boundary between **C language knowledge** and **API semantics**.

---

### 32. API mode does not parse the source into wrappers

It is easy to misunderstand API mode as:

> CFFI gives the header to a compiler and automatically exposes everything.

That is not what happens.

You still select the declarations in `cdef()`:

```python
ffibuilder.cdef("""
    int ctd_add(int a, int b);
    int ctd_subtract(int a, int b);
""")
```

The header included in `set_source()` may contain hundreds of other functions. They are not exposed merely because the compiler sees them.

`cdef()` defines the CFFI-visible interface. `set_source()` gives the compiler the real C environment needed to implement that interface. ([CFFI][1])

---

### 33. API mode with sources versus API mode with a library

There are two common API-mode deployment models.

#### A. Compile the target sources into the extension

```python
ffibuilder.set_source(
    "_ctd",
    '#include "ctd.h"',
    sources=["ctd.c"],
)
```

Artifact:

```text
_ctd.pyd
```

The target code is part of the Python extension.

##### Benefits

* one principal native artifact;
* no separately deployed target DLL may be needed;
* simple symbol resolution;
* private supporting functions can sometimes be wrapped more easily.

##### Costs

* Python binding build compiles the target code;
* you may test a separate copy rather than the production DLL;
* build options must exactly match desired production behavior;
* duplicated state can occur if the process also loads another copy of the same library.

#### B. Link the extension against an existing library

```python
ffibuilder.set_source(
    "_ctd",
    '#include "ctd.h"',
    libraries=["ctd"],
)
```

Artifacts:

```text
_ctd.pyd
ctd.dll
```

##### Benefits

* the wrapper uses the actual separately built library;
* library and Python wrapper remain distinct;
* multiple consumers can share the library design.

##### Costs

* native loader and deployment complexity;
* import library requirements on Windows;
* DLL lookup concerns;
* wrapper and target library ABI must remain compatible.

---

### 34. Binary compatibility and upgrades

#### ABI mode

Suppose `ctd.dll` is replaced with a newer build.

The binding continues to work only if the binary contract remains compatible:

* same exported names;
* compatible signatures;
* compatible structure layouts;
* compatible enum and constant expectations;
* compatible calling conventions;
* compatible ownership behavior.

Because no build step checks the replacement, incompatibility may surface only at runtime.

#### API mode

A compiled `_ctd.pyd` also depends on an ABI-compatible target library if dynamically linked.

Including the header at extension-build time does not protect against replacing the DLL later with an incompatible version.

API mode verifies the relationship between:

```text
header seen at wrapper-build time
and
wrapper generated at wrapper-build time
```

It does not prove compatibility with every DLL that might later be installed.

The strongest deployment discipline is to build and package the extension and target library from the same versioned source or SDK.

---

### 35. Debug and release variants

ABI mode makes switching variants straightforward:

```python
lib = ffi.dlopen(debug_dll_path)
```

You can run identical Python wrappers against:

* debug build;
* release build;
* instrumented build;
* fault-injection build;
* test-export build.

API mode can also support variants, but usually through:

* rebuilding the extension;
* changing loader paths;
* replacing a dependency with an ABI-compatible build;
* producing separate extension modules.

For a C unit-test exposure layer, ABI mode can therefore be operationally simpler even though API mode is technically safer.

---

### 36. Suitability for automated binding generation

For your generator, both are possible backends.

#### ABI backend output

The generator emits:

```python
ffi.cdef("""
    int32_t ctd_scalar_zero(void);
    int32_t ctd_scalar_one(int32_t value);
""")
```

and:

```python
lib = ffi.dlopen(dll_path)
```

Then it emits semantic wrappers based on your annotations.

##### Generator advantages

* no generated C extension build;
* test DLL selected at runtime;
* compact machinery;
* easy pytest integration;
* close fit for generated, explicit C99 declarations;
* one Python binding can test multiple builds.

##### Generator burden

* exact ABI types must be generated;
* structure layouts are hazardous;
* calling convention must be represented;
* declaration errors become runtime hazards.

#### API backend output

The generator emits:

```python
ffibuilder.cdef("""
    int32_t ctd_scalar_zero(void);
    int32_t ctd_scalar_one(int32_t value);
""")
```

and:

```python
ffibuilder.set_source(
    "_ctd",
    """
    #include "ctd_test_api.h"
    """,
    libraries=["ctd_test"],
)
```

##### Generator advantages

* compiler participates in validation;
* better support for structures and platform typedefs;
* direct compiled calls;
* better performance;
* easier support for inline or macro adapters.

##### Generator burden

* native build step;
* Python extension packaging;
* compiler/Python compatibility;
* library discovery and linking;
* more complex test-build orchestration;
* less convenient arbitrary-DLL selection.

---

### 37. Comparison table

| Dimension                                | ABI mode                             | API mode                                    |
| ---------------------------------------- | ------------------------------------ | ------------------------------------------- |
| Calls library through                    | Dynamic binary interface             | Compiled C wrapper                          |
| Normal library access                    | `ffi.dlopen()`                       | Imported generated `lib`                    |
| Project-specific C compiler needed       | No                                   | Yes                                         |
| Generated native Python extension        | No, except CFFI runtime itself       | Yes                                         |
| `cdef()` correctness burden              | Very high                            | Lower, compiler-assisted                    |
| Header included by compiler              | No                                   | Yes                                         |
| Exact struct layout required in `cdef()` | Usually yes                          | Often compiler can fill gaps                |
| Platform typedef handling                | Must match ABI exactly               | Compiler resolves actual type               |
| Inline functions                         | Not directly callable without symbol | Callable through compiled code              |
| Function-like macros                     | Not directly callable                | Can be wrapped in C                         |
| Static/private symbols                   | Not available from DLL               | Only if visible in compiled wrapper context |
| Runtime library selection                | Easy                                 | Less direct                                 |
| Calls to tiny functions                  | Slower                               | Faster                                      |
| Import-time declaration parsing          | Inline ABI: yes                      | No at normal runtime                        |
| Errors discovered                        | Often runtime                        | Many moved to build time                    |
| Distribution                             | Python code plus DLL                 | Platform-specific extension, possibly DLL   |
| Best for quick DLL testing               | Strong                               | Often excessive                             |
| Best for complex production binding      | Limited                              | Strong                                      |
| Semantic wrapper generation              | Still required                       | Still required                              |

---

### 38. Decision rules

#### Prefer ABI mode when

* the target is already built as a DLL;
* you need to select the DLL path at test runtime;
* the interface is controlled and simple;
* types are fixed-width;
* structures are opaque or avoided;
* exports are specifically designed for testing;
* you want no extra compiled Python extension;
* call overhead is not dominant;
* your generator can reliably emit exact declarations.

For your controlled test fixture, this profile might look like:

```c
int32_t ctd_scalar_zero(void);
int32_t ctd_scalar_one(int32_t value);

int ctd_array_copy(
    const int32_t *input,
    size_t count,
    int32_t *output
);
```

That is a reasonable ABI-mode target.

#### Prefer API mode when

* the public header is the authoritative interface;
* structures must be inspected;
* platform-dependent typedefs are common;
* macros and inline functions matter;
* performance of frequent calls matters;
* a compiler build step is acceptable;
* the binding is intended for stable production distribution;
* compiler-assisted checking is valuable;
* the target API is broad and native-platform-oriented.

---

### 39. Recommendation for your testing system

Given your stated scope:

* C module built as a test DLL;
* pytest is the runner;
* selected internal functions are exported under a test macro;
* declarations are extracted algorithmically;
* pointer semantics are supplied through a compact annotation policy;
* Python copies returned data;
* no ambition to cover arbitrary C;
* preference for minimal machinery;

**ABI mode is probably the better initial execution backend.**

The main reasons are operational:

1. The test DLL is already your artifact under test.
2. `ffi.dlopen(path)` lets pytest load that exact artifact.
3. You avoid building and versioning an additional `_module.pyd`.
4. Your restricted interface can deliberately exclude the ABI features that make ABI mode hazardous.
5. Your semantic annotation layer is required regardless of mode.

To make that choice robust, constrain the accepted C surface:

* fixed-width integer types;
* `size_t` only where process architecture is guaranteed to match;
* ordinary C calling convention, or explicitly captured convention;
* no by-value structures or unions initially;
* no bit-fields;
* no variadic functions;
* no compiler-specific vector types;
* no long-double portability claims;
* opaque structure pointers only;
* exported functions only;
* explicit string and pointer annotations;
* identical architecture for Python and DLL.

API mode would become attractive later if you expand toward:

* by-value structures;
* compiler-selected layouts;
* broad third-party headers;
* macros and inline functions;
* highly performance-sensitive scalar calls;
* production bindings rather than controlled test bindings.

The essential conclusion is:

> **ABI mode trusts your generated binary declaration. API mode asks a C compiler to mediate between your CFFI declaration and the actual C interface.**

Neither mode supplies the higher-level meaning of pointers, arrays, buffers, ownership, nullability, or strings. That remains the core job of your policy and wrapper generator.

[1]: https://cffi.readthedocs.io/en/stable/overview.html "Overview — CFFI 2.1.0 documentation"
[2]: https://cffi.readthedocs.io/en/latest/whatsnew.html "What’s New — CFFI 2.2.0.dev0 documentation"
