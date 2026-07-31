---
url: https://chatgpt.com/c/6a6add0f-1f70-83eb-b67e-b8e80aaf9903
---

## 📗 Introspection via `lib`

> [!NOTE] Prompt
> 
> Ok, so I have ctd ext built.  Now, how can use lib to verify that specific global constants name are defined and verify their values?

Use normal Python attribute inspection on `lib`.

For a single constant:

```python
name = "CTD_OK"
expected = 0

assert hasattr(lib, name), f"{name} is not defined"
actual = getattr(lib, name)

assert isinstance(actual, int)
assert actual == expected, f"{name}: expected {expected}, got {actual}"
```

For several constants:

```python
EXPECTED_CONSTANTS = {
    "CTD_OK": 0,
    "CTD_ERROR_NULL": 1,
    "CTD_ERROR_RANGE": 2,
    "CTD_ERROR_CAPACITY": 3,
    "CTD_ERROR_ALLOCATION": 4,
    "CTD_ERROR_DIVIDE_BY_ZERO": 5,
}


for name, expected in EXPECTED_CONSTANTS.items():
    assert hasattr(lib, name), f"{name} is not defined"

    actual = getattr(lib, name)

    assert isinstance(actual, int), (
        f"{name} should be a Python int, got {type(actual).__name__}"
    )
    assert actual == expected, (
        f"{name}: expected {expected}, got {actual}"
    )
```

A reusable helper:

```python
def assert_lib_constant(name: str, expected: int) -> None:
    try:
        actual = getattr(lib, name)
    except AttributeError as exc:
        raise AssertionError(f"{name} is not defined by the CFFI lib object") from exc

    assert isinstance(actual, int), (
        f"{name} should be a Python int, got {type(actual).__name__}"
    )
    assert actual == expected, (
        f"{name}: expected {expected}, got {actual}"
    )
```

Usage:

```python
assert_lib_constant("CTD_OK", 0)
assert_lib_constant("CTD_ERROR_NULL", 1)
```

For discovering names:

```python
names = [name for name in dir(lib) if name.startswith("CTD_")]
print(names)
```

But `dir(lib)` is useful for inspection, not the strongest test. For verification, `getattr()` plus `AttributeError` handling is better because it directly tests the exact required name.

---
---

## 📗 Pytest Patterns

> [!NOTE] Prompt
> 
> I do not need an exception this code will be used by pytest in bulk. It will be pytest's responsibility to provide feedback.

Then keep it direct:

```python
EXPECTED_CONSTANTS = {
    "CTD_OK": 0,
    "CTD_ERROR_NULL": 1,
    "CTD_ERROR_RANGE": 2,
    "CTD_ERROR_CAPACITY": 3,
    "CTD_ERROR_ALLOCATION": 4,
    "CTD_ERROR_DIVIDE_BY_ZERO": 5,
}


def test_constants() -> None:
    for name, expected in EXPECTED_CONSTANTS.items():
        assert getattr(lib, name) == expected
```

For better pytest parameterization:

```python
import pytest


@pytest.mark.parametrize(
    ("name", "expected"),
    [
        ("CTD_OK", 0),
        ("CTD_ERROR_NULL", 1),
        ("CTD_ERROR_RANGE", 2),
        ("CTD_ERROR_CAPACITY", 3),
        ("CTD_ERROR_ALLOCATION", 4),
        ("CTD_ERROR_DIVIDE_BY_ZERO", 5),
    ],
)
def test_constant(name: str, expected: int) -> None:
    assert getattr(lib, name) == expected
```

A missing attribute already causes pytest to report `AttributeError`, and a wrong value produces an assertion failure.

---
---

## 📗 Global Variables

> [!NOTE] Prompt
> 
> Now, global vars: names and initial values, not necessarily strict equality. This includes numeric scalars, strings, and structs.

Use a table of global names plus validator functions. `getattr(lib, name)` verifies that the symbol exists; the validator checks the initial value without requiring universal equality semantics.

```python
from collections.abc import Callable
from typing import Any

import pytest

from _ctd_wrapper import ffi, lib


GlobalValidator = Callable[[Any], bool]


GLOBAL_CASES: list[tuple[str, GlobalValidator]] = [
    # Numeric scalars
    ("ctd_global_counter", lambda value: value == 0),
    ("ctd_global_constant", lambda value: value > 0),

    # NUL-terminated string pointer or character array
    ("ctd_global_name", lambda value: ffi.string(value) == b"ctd"),

    # Structure
    (
        "ctd_global_point",
        lambda value: value.x == 2.0 and value.y == 3.0,
    ),
]


@pytest.mark.parametrize(("name", "validator"), GLOBAL_CASES)
def test_global_initial_value(
    name: str,
    validator: GlobalValidator,
) -> None:
    value = getattr(lib, name)
    assert validator(value)
```

A missing global naturally produces `AttributeError`; a bad initial value produces an ordinary assertion failure.

### Prefer dedicated validators

For readable bulk tests:

```python
from typing import Any


def is_zero(value: Any) -> bool:
    return value == 0


def is_positive_integer(value: Any) -> bool:
    return isinstance(value, int) and value > 0


def is_ctd_string(value: Any) -> bool:
    return value != ffi.NULL and ffi.string(value) == b"ctd"


def is_initial_point(value: Any) -> bool:
    return value.x == 2.0 and value.y == 3.0
```

```python
GLOBAL_CASES = [
    ("ctd_global_counter", is_zero),
    ("ctd_global_constant", is_positive_integer),
    ("ctd_global_name", is_ctd_string),
    ("ctd_global_point", is_initial_point),
]
```

### Better pytest IDs

```python
@pytest.mark.parametrize(
    ("name", "validator"),
    GLOBAL_CASES,
    ids=[name for name, _ in GLOBAL_CASES],
)
def test_global_initial_value(name: str, validator: GlobalValidator) -> None:
    assert validator(getattr(lib, name))
```

Pytest will report cases individually:

```text
test_global_initial_value[ctd_global_counter]
test_global_initial_value[ctd_global_constant]
test_global_initial_value[ctd_global_name]
test_global_initial_value[ctd_global_point]
```

### Different string global forms

These C declarations require slightly different checks.

#### Character pointer

```c
extern const char *ctd_global_name;
```

```python
def is_ctd_string(value: Any) -> bool:
    return value != ffi.NULL and ffi.string(value) == b"ctd"
```

#### Fixed character array

```c
extern const char ctd_global_name[16];
```

The same conversion works:

```python
ffi.string(value)
```

#### Nullable string

```python
def is_null_string(value: Any) -> bool:
    return value == ffi.NULL
```

or:

```python
def is_optional_ctd_string(value: Any) -> bool:
    return value == ffi.NULL or ffi.string(value) == b"ctd"
```

### Structures

For:

```c
extern ctd_point ctd_global_point;
```

CFFI exposes a struct cdata value, so inspect its fields directly:

```python
def is_initial_point(value: Any) -> bool:
    return (
        value.x == pytest.approx(2.0)
        and value.y == pytest.approx(3.0)
    )
```

For floating-point fields, `pytest.approx()` is preferable to exact equality:

```python
def is_initial_stats(value: Any) -> bool:
    return (
        value.count == 3
        and value.minimum == 1
        and value.maximum == 5
        and value.sum == 9
        and value.mean == pytest.approx(3.0)
    )
```

### Declarative expected values

Another useful design is to separate extraction from comparison:

```python
GLOBAL_CASES = [
    ("ctd_global_counter", lambda value: value, 0),
    ("ctd_global_constant", lambda value: value, 1729),
    ("ctd_global_name", ffi.string, b"ctd"),
    (
        "ctd_global_point",
        lambda value: (value.x, value.y),
        pytest.approx((2.0, 3.0)),
    ),
]


@pytest.mark.parametrize(
    ("name", "extract", "expected"),
    GLOBAL_CASES,
    ids=[case[0] for case in GLOBAL_CASES],
)
def test_global_initial_value(
    name: str,
    extract: Callable[[Any], Any],
    expected: Any,
) -> None:
    assert extract(getattr(lib, name)) == expected
```

This is preferable when each global has a definite expected representation. Use predicate validators when the accepted initial state is a range, set, structural condition, nullable alternative, or other non-equality contract.

One important requirement: these tests must run before any test mutates the globals, or each mutating test must restore the original state. Initial-value tests are otherwise order-dependent.

---
---

## 📗 Enum Values - C vs. Python

> [!NOTE] Prompt
> 
> With enumes, how do I amend parametrization such that instead of hard coding individual values, a python enum class mirroring the target c enum is used instead for both names and values?

Use the Python `IntEnum` itself as the parameter source. Each member gives you both the C symbol name and expected integer value.

```python
from enum import IntEnum

import pytest

from _ctd_wrapper import lib


class CtdStatus(IntEnum):
    CTD_OK = 0
    CTD_ERROR_NULL = 1
    CTD_ERROR_RANGE = 2
    CTD_ERROR_CAPACITY = 3
    CTD_ERROR_ALLOCATION = 4
    CTD_ERROR_DIVIDE_BY_ZERO = 5
```

Then parametrize directly over the enum members:

```python
@pytest.mark.parametrize("member", CtdStatus)
def test_ctd_status_constant(member: CtdStatus) -> None:
    assert getattr(lib, member.name) == member.value
```

Pytest will generate one case per member.

For clearer test IDs:

```python
@pytest.mark.parametrize(
    "member",
    list(CtdStatus),
    ids=lambda member: member.name,
)
def test_ctd_status_constant(member: CtdStatus) -> None:
    assert getattr(lib, member.name) == member.value
```

You can also unpack name and value during parametrization:

```python
@pytest.mark.parametrize(
    ("name", "expected"),
    [(member.name, member.value) for member in CtdStatus],
)
def test_ctd_status_constant(name: str, expected: int) -> None:
    assert getattr(lib, name) == expected
```

The first form is cleaner because the enum remains the single authoritative Python mirror:

```python
@pytest.mark.parametrize(
    "member",
    CtdStatus,
    ids=lambda member: member.name,
)
def test_ctd_status_constant(member: CtdStatus) -> None:
    assert getattr(lib, member.name) == member
```

That last assertion works because `IntEnum` members compare equal to their underlying integer values. I would still prefer `.value` for explicitness:

```python
assert getattr(lib, member.name) == member.value
```

---
---

## 📗 Enum Type

> [!NOTE] Prompt
> 
> Is enum type exposed on lib to also  verify its name? I mean, if I access enum members in c, I also need to use enum name?

No. CFFI does **not** expose the enum type name as `lib.ctd_status`.

`lib` exposes runtime C symbols and constants, such as:

```python
lib.CTD_OK
lib.CTD_ERROR_NULL
```

The type is accessed through `ffi`:

```python
enum_type = ffi.typeof("ctd_status")

assert enum_type.kind == "enum"
assert enum_type.cname == "ctd_status"
```

For your declaration:

```c
typedef enum ctd_status {
    CTD_OK = 0,
    CTD_ERROR_NULL = 1
} ctd_status;
```

there are two C names:

* `enum ctd_status` — the enum tag;
* `ctd_status` — the typedef name.

You can verify either through CFFI:

```python
assert ffi.typeof("ctd_status").kind == "enum"
assert ffi.typeof("ctd_status").cname == "ctd_status"

assert ffi.typeof("enum ctd_status").kind == "enum"
assert ffi.typeof("enum ctd_status").cname == "enum ctd_status"
```

Depending on CFFI’s canonicalization, comparing the type objects is more useful than requiring identical `cname` strings:

```python
assert ffi.typeof("ctd_status") == ffi.typeof("enum ctd_status")
```

A pytest test could be:

```python
def test_ctd_status_type() -> None:
    enum_type = ffi.typeof("ctd_status")

    assert enum_type.kind == "enum"
    assert enum_type == ffi.typeof("enum ctd_status")
```

### In C, enum members do not use the enum name

C enum enumerators are placed in the ordinary identifier namespace. You write:

```c
ctd_status status = CTD_OK;
```

not:

```c
ctd_status status = ctd_status.CTD_OK;  /* invalid C */
```

The enum name is required when declaring the type:

```c
ctd_status status;
enum ctd_status other_status;
```

But the members themselves are unscoped:

```c
CTD_OK
CTD_ERROR_NULL
```

That maps naturally to CFFI:

```python
ffi.typeof("ctd_status")  # type information
lib.CTD_OK                # enumerator value
```

Therefore, verifying the enum fully requires two separate tests:

```python
def test_ctd_status_type() -> None:
    assert ffi.typeof("ctd_status").kind == "enum"
    assert ffi.typeof("ctd_status") == ffi.typeof("enum ctd_status")


@pytest.mark.parametrize(
    "member",
    CtdStatus,
    ids=lambda member: member.name,
)
def test_ctd_status_member(member: CtdStatus) -> None:
    assert getattr(lib, member.name) == member.value
```

---
---

## 📗 C Enum Use

> [!NOTE] Prompt
> 
> So, I do not really care about enum type/tag names? If members are verified, the same unscoped members will work in c? 

Correct. For ordinary C enum usage, **the enumerator names and values are what matter operationally**.

Given:

```c
typedef enum ctd_status {
    CTD_OK = 0,
    CTD_ERROR_NULL = 1
} ctd_status;
```

C code uses:

```c
ctd_status status = CTD_OK;

if(status == CTD_ERROR_NULL){
    /* ... */
}
```

The members are unscoped identifiers. They are not accessed through the tag or typedef:

```c
ctd_status.CTD_OK       /* invalid C */
enum ctd_status.CTD_OK  /* invalid C */
```

Therefore, this verifies the constants callers actually use:

```python
@pytest.mark.parametrize(
    "member",
    CtdStatus,
    ids=lambda member: member.name,
)
def test_ctd_status_member(member: CtdStatus) -> None:
    assert getattr(lib, member.name) == member.value
```

The enum type name matters only where the type itself appears in the API, for example:

```c
ctd_status ctd_divide(...);
void ctd_set_status(ctd_status status);
ctd_status global_status;
```

But CFFI already compiled and exposed those declarations. If the typedef or tag name were incorrect in `cdef()`, the generated extension would generally fail to compile against the real header or would expose a different declared interface.

So for runtime tests:

- verify enumerator names and values;
- test functions accepting or returning the enum;
- usually do not separately test the enum tag or typedef name.

A separate `ffi.typeof("ctd_status")` test is worthwhile only when validating the generated binding’s declared type surface itself, rather than testing the C module’s behavior.

---
---

## 📗 C Contract Testing

> [!NOTE] Prompt
> 
> I need tests to verify the structures are there!

Correct. You need explicit contract tests for declared types, including structs, unions, enums, typedefs, and opaque types.

CFFI exposes those through `ffi.typeof()`, not `lib`.

For a struct typedef:

```c
typedef struct ctd_point {
    double x;
    double y;
} ctd_point;
```

verify both existence and structure:

```python
def test_ctd_point_type() -> None:
    ctype = ffi.typeof("ctd_point")

    assert ctype.kind == "struct"
    assert [field_name for field_name, _ in ctype.fields] == ["x", "y"]
```

For field types:

```python
def test_ctd_point_fields() -> None:
    ctype = ffi.typeof("ctd_point")
    fields = dict(ctype.fields)

    assert fields["x"].type.cname == "double"
    assert fields["y"].type.cname == "double"
```

For `ctd_stats`:

```python
def test_ctd_stats_type() -> None:
    ctype = ffi.typeof("ctd_stats")
    fields = dict(ctype.fields)

    assert ctype.kind == "struct"
    assert list(fields) == [
        "count",
        "minimum",
        "maximum",
        "sum",
        "mean",
    ]

    assert fields["count"].type.cname == "size_t"
    assert fields["minimum"].type.cname == "int32_t"
    assert fields["maximum"].type.cname == "int32_t"
    assert fields["sum"].type.cname == "int64_t"
    assert fields["mean"].type.cname == "double"
```

For fixed arrays inside structs:

```python
def test_ctd_record_type() -> None:
    ctype = ffi.typeof("ctd_record")
    fields = dict(ctype.fields)

    assert fields["id"].type.cname == "int32_t"

    assert fields["name"].type.kind == "array"
    assert fields["name"].type.item.cname == "char"
    assert fields["name"].type.length == 16

    assert fields["values"].type.kind == "array"
    assert fields["values"].type.item.cname == "double"
    assert fields["values"].type.length == 3
```

For a union:

```python
def test_ctd_number_type() -> None:
    ctype = ffi.typeof("ctd_number")
    fields = dict(ctype.fields)

    assert ctype.kind == "union"
    assert list(fields) == ["i64", "f64"]
    assert fields["i64"].type.cname == "int64_t"
    assert fields["f64"].type.cname == "double"
```

For an enum type:

```python
def test_ctd_status_type() -> None:
    ctype = ffi.typeof("ctd_status")

    assert ctype.kind == "enum"
```

And separately verify its members through `lib`:

```python
@pytest.mark.parametrize(
    "member",
    CtdStatus,
    ids=lambda member: member.name,
)
def test_ctd_status_member(member: CtdStatus) -> None:
    assert getattr(lib, member.name) == member.value
```

For an opaque type:

```c
typedef struct ctd_counter ctd_counter;
```

verify that it exists and remains incomplete:

```python
def test_ctd_counter_type() -> None:
    ctype = ffi.typeof("ctd_counter")

    assert ctype.kind == "struct"
    assert ctype.fields is None
```

For callback typedefs:

```python
def test_ctd_binary_callback_type() -> None:
    ctype = ffi.typeof("ctd_binary_callback")

    assert ctype.kind == "function"
    assert ctype.result.cname == "int"
    assert [arg.cname for arg in ctype.args] == [
        "int",
        "int",
        "void *",
    ]
```

Depending on CFFI representation, function-pointer typedefs may appear as a pointer whose item is the function type. A robust version is:

```python
def unwrap_function_pointer(ctype):
    if ctype.kind == "pointer":
        ctype = ctype.item

    assert ctype.kind == "function"
    return ctype
```

Then:

```python
def test_ctd_binary_callback_type() -> None:
    ctype = unwrap_function_pointer(ffi.typeof("ctd_binary_callback"))

    assert ctype.result.cname == "int"
    assert [arg.cname for arg in ctype.args] == [
        "int",
        "int",
        "void *",
    ]
```

The correct boundary is therefore:

* `ffi.typeof("name")` verifies declared C types exist and have the expected shape.
* `lib.NAME` verifies exposed constants, enum members, globals, and functions.
* Function calls verify behavior.

That is the complete contract surface you are trying to test.

---
---

## 📗 C Contract - Global Type, Variables, Constants, Namespace

> [!NOTE] Prompt
> 
> So, cdef declarations may contain **types, functions, constants** and **global variables**, and I need comprehensive systematic testing strategy. Unit testing of functions is the second part, but first I want to get in order already touched types/typedefs, constants, and variables. I want to leave unions out for now, as this is specific low-level target beyond my present interests. So, I guess, we should limit scope for typedefs to structs and enums. I understand that I can inspect (and ultimately pytest) all names and types.
> 
> For constants, I should be able to verify both name a value (I might define a Python datatclass CConstants or CConst (or similar) for convenient verification of constant names and values).
> 
> For variables, I can probably also define CVariable(s)/CVar(s) and use it for automatic verification of variable names and types. I could also, possibly, add setters to define expected constraints (perhaps positive or zero intimal numeric values, or specific strings).
> 
> There is of course the need to consider non-scalar constants and variables as to what is the practical limit to automatic generic verification via Python classes. 
> 
> For enums, targets include names and values of enum members, enum tag (`enum ctd_status`), enum name (`ctd_status`), types of both. Members can be tested conveniently against Python-defined `IntEnum` subclass mirroring C enum.
> 
> For structs, similarly, I would want to verify struct tag (`struct ctd_point`), struct name (`ctd_point`), types of both, fields and there names and types (possibly also by defining a "mirror" Python class to be used as a reference "template")?

Yes. That is the right decomposition, but the contract model should distinguish **declared types**, **value constants**, and **objects with storage**. They are exposed differently by CFFI and require different verification mechanisms.

CFFI’s runtime introspection is sufficient for a systematic first-stage contract suite: `ffi.typeof()` exposes named C types, while `lib` exposes declared functions, constants, and globals. `CType` objects provide attributes such as `kind`, `cname`, `fields`, `elements`, and `relements`, depending on the type category. ([CFFI][1])

### 1. Recommended scope

For the first phase, cover:

1. Struct types and their typedefs
2. Enum types and their typedefs
3. Enum members and integer constants
4. Global variables:
    * numeric scalars;
    * character arrays;
    * character pointers;
    * fixed-size arrays;
    * struct objects
5. Explicitly exclude for now:
    * unions;
    * bitfields;
    * flexible array members;
    * arbitrary pointer graphs;
    * function pointers;
    * recursively linked structures;
    * semantic ownership and lifetime validation

That is a coherent and broad enough subset.

---

### 2. Terminology

Consider:

```c
typedef struct ctd_point {
    double x;
    double y;
} ctd_point;
```

This declares:

* struct tag: `struct ctd_point`
* typedef name: `ctd_point`

Likewise:

```c
typedef enum ctd_status {
    CTD_OK = 0
} ctd_status;
```

declares:

* enum tag: `enum ctd_status`
* typedef name: `ctd_status`
* enumerator: `CTD_OK`

These are separate contract names and can all be tested.

---

### 3. A common type reference

Use strings containing C type syntax as your canonical expected type references:

```python
from dataclasses import dataclass


@dataclass(frozen=True)
class CTypeRef:
    spelling: str
```

Examples:

```python
CTypeRef("int32_t")
CTypeRef("double")
CTypeRef("char[16]")
CTypeRef("struct ctd_point")
CTypeRef("ctd_point")
```

Do not generally compare `cname` strings to determine type equivalence. Instead, resolve the expected type through the same `ffi` instance:

```python
def assert_same_c_type(actual, expected: CTypeRef) -> None:
    assert actual == ffi.typeof(expected.spelling)
```

This lets CFFI handle typedef resolution and canonicalization.

---

### 4. Enum contract

A useful enum specification is:

```python
from dataclasses import dataclass
from enum import IntEnum
from typing import type as type_type
```

More practically:

```python
from dataclasses import dataclass
from enum import IntEnum


@dataclass(frozen=True)
class CEnumSpec:
    typedef_name: str
    tag_name: str
    mirror: type[IntEnum]
```

Mirror:

```python
class CtdStatus(IntEnum):
    CTD_OK = 0
    CTD_ERROR_NULL = 1
    CTD_ERROR_RANGE = 2
    CTD_ERROR_CAPACITY = 3
    CTD_ERROR_ALLOCATION = 4
    CTD_ERROR_DIVIDE_BY_ZERO = 5
```

Specification:

```python
CTD_STATUS = CEnumSpec(
    typedef_name="ctd_status",
    tag_name="enum ctd_status",
    mirror=CtdStatus,
)
```

#### Enum type verification

```python
def verify_enum_type(spec: CEnumSpec) -> None:
    typedef_type = ffi.typeof(spec.typedef_name)
    tagged_type = ffi.typeof(spec.tag_name)

    assert typedef_type.kind == "enum"
    assert tagged_type.kind == "enum"
    assert typedef_type == tagged_type
```

This verifies that:

* `ctd_status` exists;
* `enum ctd_status` exists;
* both designate the same enum type.

#### Enumerator verification through `lib`

```python
import pytest


@pytest.mark.parametrize(
    "member",
    list(CtdStatus),
    ids=lambda member: member.name,
)
def test_ctd_status_member(member: CtdStatus) -> None:
    assert getattr(lib, member.name) == member.value
```

You can also cross-check CFFI’s enum metadata:

```python
def verify_enum_members(spec: CEnumSpec) -> None:
    ctype = ffi.typeof(spec.typedef_name)

    expected = {
        member.name: member.value
        for member in spec.mirror
    }

    assert ctype.relements == expected

    for member in spec.mirror:
        assert getattr(lib, member.name) == member.value
```

CFFI enum types expose `elements` and `relements` for value-to-name and name-to-value inspection. ([CFFI][2])

Using both mechanisms verifies two distinct surfaces:

* `ctype.relements`: the enum declaration known to CFFI;
* `lib.CTD_OK`: the public constant exposed to Python.

---

### 5. Struct contract

Define fields explicitly:

```python
@dataclass(frozen=True)
class CFieldSpec:
    name: str
    type: CTypeRef


@dataclass(frozen=True)
class CStructSpec:
    typedef_name: str
    tag_name: str
    fields: tuple[CFieldSpec, ...]
```

For `ctd_point`:

```python
CTD_POINT = CStructSpec(
    typedef_name="ctd_point",
    tag_name="struct ctd_point",
    fields=(
        CFieldSpec("x", CTypeRef("double")),
        CFieldSpec("y", CTypeRef("double")),
    ),
)
```

For `ctd_record`:

```python
CTD_RECORD = CStructSpec(
    typedef_name="ctd_record",
    tag_name="struct ctd_record",
    fields=(
        CFieldSpec("id", CTypeRef("int32_t")),
        CFieldSpec("name", CTypeRef("char[16]")),
        CFieldSpec("values", CTypeRef("double[3]")),
    ),
)
```

#### Generic struct verifier

```python
def verify_struct_type(spec: CStructSpec) -> None:
    typedef_type = ffi.typeof(spec.typedef_name)
    tagged_type = ffi.typeof(spec.tag_name)

    assert typedef_type.kind == "struct"
    assert tagged_type.kind == "struct"
    assert typedef_type == tagged_type

    assert typedef_type.fields is not None

    actual_fields = typedef_type.fields

    assert [name for name, _ in actual_fields] == [
        field.name for field in spec.fields
    ]

    for expected, (actual_name, actual_field) in zip(
        spec.fields,
        actual_fields,
        strict=True,
    ):
        assert actual_name == expected.name
        assert actual_field.type == ffi.typeof(expected.type.spelling)
```

This verifies:

* struct typedef exists;
* struct tag exists;
* both refer to the same type;
* the type is a struct;
* fields appear in the expected order;
* field names match;
* field types match;
* fixed array element types and lengths match automatically through type equality.

#### Optional layout verification

You may additionally verify:

```python
ffi.sizeof("ctd_point")
ffi.alignof("ctd_point")
ffi.offsetof("ctd_point", "x")
ffi.offsetof("ctd_point", "y")
```

But I would keep layout tests separate:

```python
@dataclass(frozen=True)
class CStructLayout:
    size: int
    alignment: int
    offsets: dict[str, int]
```

Layout is platform- and compiler-dependent. Since your API-mode build already uses the real compiler, exact layout assertions are useful only when binary layout is itself part of your expected contract—for example, serialized records, shared memory, or an externally fixed ABI.

---

### 6. Opaque structs

Although you may not need them in the first type subset, `ctd_counter` is worth distinguishing:

```c
typedef struct ctd_counter ctd_counter;
```

It is a named incomplete struct, not a defined struct.

```python
@dataclass(frozen=True)
class COpaqueStructSpec:
    typedef_name: str
    tag_name: str
```

Verifier:

```python
def verify_opaque_struct(spec: COpaqueStructSpec) -> None:
    typedef_type = ffi.typeof(spec.typedef_name)
    tagged_type = ffi.typeof(spec.tag_name)

    assert typedef_type.kind == "struct"
    assert tagged_type.kind == "struct"
    assert typedef_type == tagged_type
    assert typedef_type.fields is None
```

This explicitly verifies that the object remains opaque.

---

### 7. Constants

You should separate three kinds of C constants:

#### Enum members

```c
CTD_OK
CTD_ERROR_NULL
```

They are exposed as Python integers on `lib`.

#### Integer macro constants

In CFFI API mode, an integer macro can be exposed when represented appropriately in the `cdef()` input, commonly with:

```c
#define CTD_CAPACITY ...
```

CFFI asks the compiler for the actual integer value and exposes it on `lib`. ([CFFI][3])

#### Typed constant objects

```c
extern const int ctd_global_constant;
```

This is not merely a compile-time constant. It is a global object with storage and an address, so it belongs under variables rather than macro constants.

#### Constant specification

For enum members and integer macros:

```python
from dataclasses import dataclass


@dataclass(frozen=True)
class CConstant:
    name: str
    value: int
```

Example:

```python
CONSTANTS = (
    CConstant("CTD_BUFFER_CAPACITY", 16),
    CConstant("CTD_DEFAULT_LIMIT", 100),
)
```

Verifier:

```python
@pytest.mark.parametrize(
    "constant",
    CONSTANTS,
    ids=lambda constant: constant.name,
)
def test_constant(constant: CConstant) -> None:
    assert getattr(lib, constant.name) == constant.value
```

A generic integer constant exposed by `lib` does not necessarily preserve enough information to verify its original source-level integer type. Its useful exposed contract is normally:

* name;
* Python integer value.

If exact C type matters, declare a typed global object instead.

---

### 8. Global variables

Variables need three independent checks:

1. Symbol name exists.
2. Declared C type matches.
3. Initial value satisfies an expected condition.

The important point is that reading a scalar global loses its C type:

```python
value = lib.ctd_global_counter
type(value)  # int
```

To recover the actual declared C type, take its address:

```python
pointer = ffi.addressof(lib, "ctd_global_counter")
variable_type = ffi.typeof(pointer).item
```

CFFI documents `ffi.addressof(lib, "name")` for obtaining the address of a named global variable or function. ([CFFI][2])

#### Variable specification

```python
from collections.abc import Callable
from dataclasses import dataclass
from typing import Any


ValueValidator = Callable[[Any], bool]


@dataclass(frozen=True)
class CVariable:
    name: str
    type: CTypeRef
    initial: ValueValidator | None = None
```

Generic verifier:

```python
def verify_variable(spec: CVariable) -> None:
    address = ffi.addressof(lib, spec.name)
    actual_type = ffi.typeof(address).item

    assert actual_type == ffi.typeof(spec.type.spelling)

    if spec.initial is not None:
        assert spec.initial(getattr(lib, spec.name))
```

Missing variables naturally fail at `ffi.addressof()` or `getattr()`.

---

### 9. Reusable initial-value constraints

Rather than arbitrary lambdas everywhere, define small explicit matcher objects.

```python
from dataclasses import dataclass
from typing import Any, Protocol


class ValueConstraint(Protocol):
    def __call__(self, value: Any) -> bool:
        ...
```

#### Exact value

```python
@dataclass(frozen=True)
class Equals:
    expected: Any

    def __call__(self, value: Any) -> bool:
        return value == self.expected
```

#### Zero

```python
@dataclass(frozen=True)
class Zero:
    def __call__(self, value: Any) -> bool:
        return value == 0
```

#### Positive number

```python
@dataclass(frozen=True)
class Positive:
    def __call__(self, value: Any) -> bool:
        return value > 0
```

#### Range

```python
@dataclass(frozen=True)
class Between:
    minimum: int | float
    maximum: int | float

    def __call__(self, value: Any) -> bool:
        return self.minimum <= value <= self.maximum
```

Then:

```python
VARIABLES = (
    CVariable(
        name="ctd_global_counter",
        type=CTypeRef("int"),
        initial=Zero(),
    ),
    CVariable(
        name="ctd_global_constant",
        type=CTypeRef("const int"),
        initial=Equals(1729),
    ),
)
```

One qualification: top-level `const` representation may be normalized by CFFI. For variable mutability, the declaration itself matters because CFFI generates write access only for non-const globals. CFFI notes that `const` on a global declaration determines whether the variable is treated as writable. ([CFFI][3])

---

### 10. String globals

C has multiple materially different “string-like” global types.

#### Fixed character array

```c
extern const char ctd_name[16];
```

Expected type:

```python
CTypeRef("const char[16]")
```

Value extraction:

```python
ffi.string(lib.ctd_name)
```

#### Character pointer

```c
extern const char *ctd_name;
```

Expected type:

```python
CTypeRef("const char *")
```

Value may be `NULL`, so validation must account for that.

#### String constraint

```python
@dataclass(frozen=True)
class CStringEquals:
    expected: str
    encoding: str = "utf-8"

    def __call__(self, value: Any) -> bool:
        return (
            value != ffi.NULL
            and ffi.string(value).decode(self.encoding) == self.expected
        )
```

Nullable variant:

```python
@dataclass(frozen=True)
class NullableCStringEquals:
    expected: str | None
    encoding: str = "utf-8"

    def __call__(self, value: Any) -> bool:
        if value == ffi.NULL:
            return self.expected is None

        return ffi.string(value).decode(self.encoding) == self.expected
```

The declaration alone does not tell you that a `char *` is NUL-terminated text, which encoding it uses, or how long the valid region is. Therefore, a generic variable verifier should not automatically interpret every `char *` as a string. That semantic choice belongs in the constraint.

---

### 11. Fixed arrays

For:

```c
extern const int32_t ctd_values[4];
```

you can generically validate both type and contents.

```python
@dataclass(frozen=True)
class ArrayEquals:
    expected: tuple[Any, ...]

    def __call__(self, value: Any) -> bool:
        return tuple(value) == self.expected
```

Specification:

```python
CVariable(
    name="ctd_values",
    type=CTypeRef("const int32_t[4]"),
    initial=ArrayEquals((1, 2, 3, 4)),
)
```

Fixed arrays are a practical automatic boundary because the element type and length are present in the C type.

Unsized arrays, pointers to arrays, or pointer-plus-length conventions require additional semantic metadata.

---

### 12. Struct-valued variables

For:

```c
extern const ctd_point ctd_origin;
```

you can provide a field constraint.

```python
@dataclass(frozen=True)
class StructFields:
    expected: dict[str, Any]

    def __call__(self, value: Any) -> bool:
        return all(
            getattr(value, name) == expected
            for name, expected in self.expected.items()
        )
```

Specification:

```python
CVariable(
    name="ctd_origin",
    type=CTypeRef("const ctd_point"),
    initial=StructFields({
        "x": 0.0,
        "y": 0.0,
    }),
)
```

For floating-point values, use an explicit approximate matcher rather than hiding approximation inside the generic struct verifier.

For example:

```python
@dataclass(frozen=True)
class Approx:
    expected: float
    relative: float = 1e-12
    absolute: float = 1e-12

    def __call__(self, value: Any) -> bool:
        return value == pytest.approx(
            self.expected,
            rel=self.relative,
            abs=self.absolute,
        )
```

A richer `StructFields` implementation can recursively apply constraints:

```python
@dataclass(frozen=True)
class StructFields:
    expected: dict[str, Any]

    def __call__(self, value: Any) -> bool:
        for name, expected in self.expected.items():
            actual = getattr(value, name)

            if callable(expected):
                if not expected(actual):
                    return False
            elif actual != expected:
                return False

        return True
```

Then:

```python
StructFields({
    "x": Approx(0.0),
    "y": Approx(0.0),
})
```

---

### 13. Practical generic-verification boundary

The following are safely generic:

| Category           | Generic checks                                         |
| ------------------ | ------------------------------------------------------ |
| Scalar type        | Exact C type                                           |
| Enum               | Tag, typedef, members, numeric values                  |
| Struct             | Tag, typedef, ordered fields, field types              |
| Opaque struct      | Tag, typedef, incompleteness                           |
| Integer constant   | Name and value                                         |
| Scalar global      | Name, C type, value constraint                         |
| Fixed array global | Name, element type, length, contents                   |
| Character array    | Name, exact array type, optional string interpretation |
| Struct global      | Name, exact struct type, selected field constraints    |

The following require semantic policy and should not be automatically guessed:

| Category                  | Missing information                                   |
| ------------------------- | ----------------------------------------------------- |
| `char *`                  | text vs bytes, encoding, NUL termination, nullability |
| arbitrary `T *`           | scalar vs array, valid length, ownership              |
| pointer inside struct     | lifetime, pointee validity, count relationship        |
| unsized array             | runtime length                                        |
| recursive structure       | traversal limits and ownership                        |
| flexible array member     | allocation size                                       |
| externally mutable global | stable initial-state timing                           |
| address-valued constant   | identity and lifetime semantics                       |

That should be the deliberate stopping point.

---

### 14. Suggested module architecture

```text
tests/
    contract/
        model.py
        constraints.py
        enums.py
        structs.py
        constants.py
        variables.py
        test_enums.py
        test_structs.py
        test_constants.py
        test_variables.py
```

`model.py`:

```python
@dataclass(frozen=True)
class CTypeRef:
    spelling: str


@dataclass(frozen=True)
class CFieldSpec:
    name: str
    type: CTypeRef


@dataclass(frozen=True)
class CStructSpec:
    typedef_name: str
    tag_name: str
    fields: tuple[CFieldSpec, ...]


@dataclass(frozen=True)
class CEnumSpec:
    typedef_name: str
    tag_name: str
    mirror: type[IntEnum]


@dataclass(frozen=True)
class CConstant:
    name: str
    value: int


@dataclass(frozen=True)
class CVariable:
    name: str
    type: CTypeRef
    initial: ValueConstraint | None = None
```

This is compact enough to remain transparent while covering the important C declaration surface.

---

### 15. Recommended test hierarchy

The first-stage suite should verify:

#### Declared type contract

* expected enum typedefs exist;
* expected enum tags exist;
* each tag and typedef pair resolve to the same type;
* expected struct typedefs exist;
* expected struct tags exist;
* each tag and typedef pair resolve to the same type;
* struct field order, names, and types match;
* opaque structs remain incomplete.

#### Constant contract

* expected constant names are exposed;
* expected integer values match;
* enum metadata and exposed enum member values agree.

#### Global-object contract

* expected global names are exposed;
* exact declared C types match;
* mutability/constness is represented correctly where relevant;
* initial values satisfy declared constraints;
* string interpretation occurs only when explicitly requested;
* fixed arrays have expected shape and values;
* struct objects have expected selected fields.

#### Function contract

This remains the second phase:

* names;
* signatures;
* behavior;
* errors;
* pointer semantics;
* memory ownership;
* callbacks.

Your proposed split is therefore sound. The principal refinement is:

> A Python mirror class is useful for enum members, but structs should be represented by an explicit `CStructSpec`, not by a normal Python data class pretending to be the struct value type.

A normal dataclass can represent expected struct **values**, but it cannot by itself represent all declaration details such as tag spelling, typedef spelling, field order, C array dimensions, pointer qualifiers, or opaque/incomplete status.

[1]: https://cffi.readthedocs.io/en/stable/overview.html "Overview — CFFI 2.1.0 documentation"
[2]: https://cffi.readthedocs.io/en/latest/ref.html "CFFI Reference — CFFI 2.2.0.dev0 documentation"
[3]: https://cffi.readthedocs.io/en/latest/cdef.html "Preparing Wrapper Modules — CFFI 2.2.0.dev0 documentation"
